import 'dart:async';
import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:rxdart/rxdart.dart';

import 'bounded_lru_set.dart';
import 'bunker_connection.dart';
import 'bunker_request.dart';

/// Internal class to track a pending request with its completer and metadata
class _PendingRequestEntry {
  final Completer<String> completer;
  final PendingSignerRequest request;
  _PendingRequestEntry(this.completer, this.request);
}

class Nip46Signer with ConcurrencyLimiterMixin implements NostrSigner {
  BunkerConnection connection;
  RelayReqs relayReqs;
  RelayPublishes relayPublishes;
  Function(String)? authCallback;

  RelayReq? subscription;

  // every relay of the bunker delivers each response
  final BoundedLruSet<String> _seenResponseIds = BoundedLruSet(maxSize: 1000);

  final _pendingRequests = <String, _PendingRequestEntry>{};
  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  String? cachedPublicKey;

  late NostrSigner localSigner;
  final LocalSignerFactory signerFactory;

  @override
  final int maxConcurrentRequests;

  /// Default bunker concurrency. NIP-46 round-trips through a relay, so the
  /// limit guards against flooding it with thousands of pending events.
  /// Lower this if you hit relay rate limits.
  static const int defaultMaxConcurrentRequests = 100;

  Nip46Signer({
    required this.connection,
    required this.relayReqs,
    required this.relayPublishes,
    this.authCallback,
    this.cachedPublicKey,
    required this.signerFactory,
    this.maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) : assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0') {
    localSigner = signerFactory.create(
      privateKey: connection.privateKey,
      publicKey: signerFactory.derivePublicKey(connection.privateKey),
    );

    listenRelays();
  }

  Future<void> listenRelays() async {
    final filter = Filter(
      authors: [connection.remotePubkey],
      kinds: [BunkerRequest.kKind],
      pTags: [localSigner.getPublicKey()],
    );
    subscription = relayReqs.req(
      relays: {
        for (final relay in connection.relays) relay: [filter],
      },
      closeOnEose: false,
    );

    subscription!.events
        .map((received) => received.event)
        .where((event) => _seenResponseIds.add(event.id))
        .listen(onEvent);
  }

  Future<void> onEvent(Nip01Event event) async {
    final decryptedContent = await localSigner.decryptNip44(
      ciphertext: event.content,
      senderPubkey: event.pubkey,
    );

    final response = jsonDecode(decryptedContent!);

    if (response["result"] == "auth_url") {
      if (authCallback != null) {
        authCallback!(response["error"]);
      }
      return;
    }

    if (_pendingRequests[response["id"]] != null) {
      final entry = _pendingRequests.remove(response["id"])!;
      _notifyPendingRequestsChange();

      if (response["error"] != null && response["result"] != "auth_url") {
        entry.completer.completeError(
          SignerRequestRejectedException(
            requestId: response["id"],
            originalMessage: response["error"],
          ),
        );
      } else {
        final result = response["result"];
        entry.completer.complete(
          result is String ? result : jsonEncode(result),
        );
      }
    }
  }

  void _notifyPendingRequestsChange() {
    _pendingRequestsController.add(
      _pendingRequests.values.map((e) => e.request).toList(),
    );
  }

  Future<String> remoteRequest({
    required BunkerRequest request,
    Nip01Event? event,
    String? plaintext,
    String? ciphertext,
    String? counterpartyPubkey,
  }) async {
    final completer = Completer<String>();
    final pendingRequest = PendingSignerRequest(
      id: request.id,
      method: request.method,
      createdAt: DateTime.now(),
      signerPubkey: cachedPublicKey ?? '',
      event: event,
      plaintext: plaintext,
      ciphertext: ciphertext,
      counterpartyPubkey: counterpartyPubkey,
    );
    _pendingRequests[request.id] = _PendingRequestEntry(
      completer,
      pendingRequest,
    );
    _notifyPendingRequestsChange();

    return runThrottled(() async {
      // If the request was cancelled while queued, bail out before touching
      // the relay so we don't broadcast an event the caller no longer wants.
      if (!_pendingRequests.containsKey(request.id)) {
        throw SignerRequestCancelledException(request.id);
      }

      final encryptedRequest = await localSigner.encryptNip44(
        plaintext: jsonEncode(request),
        recipientPubkey: connection.remotePubkey,
      );

      final requestEvent = Nip01Event(
        pubkey: localSigner.getPublicKey(),
        kind: BunkerRequest.kKind,
        tags: [
          ["p", connection.remotePubkey],
        ],
        content: encryptedRequest!,
      );

      final signedEvent = await localSigner.sign(requestEvent);
      // not awaiting the broadcast: the slowest relay's OK would delay a
      // response already received through a faster one
      relayPublishes.publish(signedEvent, relays: connection.relays);

      return completer.future;
    });
  }

  @override
  bool canSign() {
    return true;
  }

  @override
  bool get requiresInteractiveSigning => true;

  @override
  bool get requiresSignerNetwork => true;

  @override
  Iterable<RelayUrl> get signerTransportRelayUrls => connection.relays;

  @override
  Future<String?> decrypt(String msg, String destPubkey) async {
    final request = BunkerRequest(
      method: SignerMethod.nip04Decrypt,
      params: [destPubkey, msg],
    );

    final decryptedText = await remoteRequest(
      request: request,
      ciphertext: msg,
      counterpartyPubkey: destPubkey,
    );
    return decryptedText;
  }

  @override
  Future<String?> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    final request = BunkerRequest(
      method: SignerMethod.nip44Decrypt,
      params: [senderPubkey, ciphertext],
    );

    final decryptedText = await remoteRequest(
      request: request,
      ciphertext: ciphertext,
      counterpartyPubkey: senderPubkey,
    );
    return decryptedText;
  }

  @override
  Future<String?> encrypt(String msg, String destPubkey) async {
    final request = BunkerRequest(
      method: SignerMethod.nip04Encrypt,
      params: [destPubkey, msg],
    );

    final encryptedText = await remoteRequest(
      request: request,
      plaintext: msg,
      counterpartyPubkey: destPubkey,
    );
    return encryptedText;
  }

  @override
  Future<String?> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    final request = BunkerRequest(
      method: SignerMethod.nip44Encrypt,
      params: [recipientPubkey, plaintext],
    );

    final encryptedText = await remoteRequest(
      request: request,
      plaintext: plaintext,
      counterpartyPubkey: recipientPubkey,
    );
    return encryptedText;
  }

  @override
  String getPublicKey() {
    if (cachedPublicKey != null) return cachedPublicKey!;
    throw Exception('Use getPublicKeyAsync() first to cache the user pubkey');
  }

  Future<String> getPublicKeyAsync() async {
    final request = BunkerRequest(method: SignerMethod.getPublicKey);

    final publicKey = await remoteRequest(request: request);

    cachedPublicKey = publicKey;

    return publicKey;
  }

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    final eventMap = {
      "kind": event.kind,
      "content": event.content,
      "tags": event.tags,
      "created_at": event.createdAt,
    };

    final request = BunkerRequest(
      method: SignerMethod.signEvent,
      params: [jsonEncode(eventMap)],
    );

    final signedEventJson = await remoteRequest(request: request, event: event);

    final signedEvent = Nip01Event.tryFromJson(jsonDecode(signedEventJson));
    if (signedEvent == null) {
      throw Exception('The remote signer returned an invalid event');
    }
    return signedEvent;
  }

  Future<String> ping() async {
    final request = BunkerRequest(method: SignerMethod.ping);

    final response = await remoteRequest(request: request);
    return response;
  }

  /// Returns the relays the remote signer moved to, or null if it keeps the
  /// current ones.
  Future<List<RelayUrl>?> switchRelays() async {
    final request = BunkerRequest(method: SignerMethod.switchRelays);

    final response = await remoteRequest(request: request);

    final decoded = jsonDecode(response);
    final relays = decoded is List
        ? cleanRelayUrls(decoded.whereType<String>())
        : const <RelayUrl>[];
    if (relays.isEmpty) return null;

    final previousSubscription = subscription;
    connection.relays = relays;
    await listenRelays();
    await previousSubscription?.close();

    return connection.relays;
  }

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      _pendingRequestsController.stream;

  @override
  List<PendingSignerRequest> get pendingRequests =>
      _pendingRequests.values.map((e) => e.request).toList();

  @override
  bool cancelRequest(String requestId) {
    final entry = _pendingRequests.remove(requestId);
    if (entry != null) {
      entry.completer.completeError(SignerRequestCancelledException(requestId));
      _notifyPendingRequestsChange();
      return true;
    }
    return false;
  }

  @override
  Future<void> dispose() async {
    cancelAllQueued();
    await subscription?.close();
    await _pendingRequestsController.close();
  }
}
