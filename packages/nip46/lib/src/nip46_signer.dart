import 'dart:async';
import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:rxdart/rxdart.dart';

import 'bounded_lru_set.dart';
import 'bunker_connection.dart';
import 'bunker_request.dart';

class _RemoteRequest {
  final completer = Completer<String>();

  /// null for a request the user does not approve, such as a ping
  final PendingSignerRequest? pending;

  _RemoteRequest(this.pending);
}

class Nip46Signer with ConcurrencyLimiterMixin implements NostrSigner {
  BunkerConnection connection;
  RelayReqs relayReqs;
  RelayPublishes relayPublishes;
  Function(String)? authCallback;

  RelayReq? subscription;

  // every relay of the bunker delivers each response
  final BoundedLruSet<String> _seenResponseIds = BoundedLruSet(maxSize: 1000);

  final _requests = <String, _RemoteRequest>{};
  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  late final String _publicKey;

  late NostrSigner localSigner;
  final LocalSignerFactory signerFactory;

  @override
  final int maxConcurrentRequests;

  /// Default bunker concurrency. NIP-46 round-trips through a relay, so the
  /// limit guards against flooding it with thousands of pending events.
  /// Lower this if you hit relay rate limits.
  static const int defaultMaxConcurrentRequests = 100;

  /// How long [connect] waits for the user's pubkey, which the bunker may ask
  /// the user to approve first.
  static const Duration defaultPublicKeyTimeout = Duration(minutes: 10);

  /// A signer for the user [publicKey] of the bunker behind [connection], such
  /// as an account restored from storage. [connect] asks the bunker for it.
  Nip46Signer({
    required BunkerConnection connection,
    required String publicKey,
    required RelayReqs relayReqs,
    required RelayPublishes relayPublishes,
    Function(String)? authCallback,
    required LocalSignerFactory signerFactory,
    int maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) : this._(
         connection: connection,
         publicKey: publicKey,
         relayReqs: relayReqs,
         relayPublishes: relayPublishes,
         authCallback: authCallback,
         signerFactory: signerFactory,
         maxConcurrentRequests: maxConcurrentRequests,
       );

  Nip46Signer._({
    required this.connection,
    required String? publicKey,
    required this.relayReqs,
    required this.relayPublishes,
    required this.authCallback,
    required this.signerFactory,
    required this.maxConcurrentRequests,
  }) : assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0') {
    if (publicKey != null) _publicKey = publicKey;
    localSigner = signerFactory.create(connection.privateKey);

    listenRelays();
  }

  /// Asks the bunker behind [connection] for the user's pubkey, and completes
  /// with a signer for it.
  ///
  /// Throws a [SignerRequestRejectedException] when the bunker refuses, and a
  /// [SignerRequestFailedException] when no valid pubkey came within
  /// [timeout].
  static Future<Nip46Signer> connect({
    required BunkerConnection connection,
    required RelayReqs relayReqs,
    required RelayPublishes relayPublishes,
    Function(String)? authCallback,
    required LocalSignerFactory signerFactory,
    int maxConcurrentRequests = defaultMaxConcurrentRequests,
    Duration timeout = defaultPublicKeyTimeout,
  }) async {
    final signer = Nip46Signer._(
      connection: connection,
      publicKey: null,
      relayReqs: relayReqs,
      relayPublishes: relayPublishes,
      authCallback: authCallback,
      signerFactory: signerFactory,
      maxConcurrentRequests: maxConcurrentRequests,
    );
    try {
      signer._publicKey = await signer._fetchPublicKey(timeout);
      return signer;
    } catch (_) {
      await signer.dispose();
      rethrow;
    }
  }

  Future<String> _fetchPublicKey(Duration timeout) async {
    final request = BunkerRequest(method: 'get_public_key');
    final String pubkey;
    try {
      pubkey = await _send(request).timeout(timeout);
    } on TimeoutException {
      throw SignerRequestFailedException(
        'The bunker sent no pubkey within $timeout',
        requestId: request.id,
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pubkey)) {
      throw SignerRequestFailedException(
        'The bunker sent an invalid pubkey',
        requestId: request.id,
        cause: pubkey,
      );
    }
    return pubkey;
  }

  Future<void> listenRelays() async {
    final filter = Filter(
      authors: [connection.remotePubkey],
      kinds: [BunkerRequest.kKind],
      pTags: [localSigner.publicKey],
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

    final response = jsonDecode(decryptedContent);

    if (response["result"] == "auth_url") {
      if (authCallback != null) {
        authCallback!(response["error"]);
      }
      return;
    }

    final entry = _requests.remove(response["id"]);
    if (entry == null) return;
    if (entry.pending != null) _notifyPendingRequestsChange();

    if (response["error"] != null) {
      entry.completer.completeError(
        SignerRequestRejectedException(
          requestId: response["id"],
          originalMessage: response["error"],
        ),
      );
    } else {
      final result = response["result"];
      entry.completer.complete(result is String ? result : jsonEncode(result));
    }
  }

  void _notifyPendingRequestsChange() {
    if (_pendingRequestsController.isClosed) return;
    _pendingRequestsController.add(pendingRequests);
  }

  /// Sends [request] to the bunker, and completes with its result. A request
  /// with a [pending] description waits in [pendingRequests] meanwhile.
  Future<String> _send(BunkerRequest request, {PendingSignerRequest? pending}) {
    final entry = _RemoteRequest(pending);
    _requests[request.id] = entry;
    if (pending != null) _notifyPendingRequestsChange();

    runThrottled(() async {
      // cancelled while queued: don't broadcast what the caller no longer wants
      if (!_requests.containsKey(request.id)) return;

      final encryptedRequest = await localSigner.encryptNip44(
        plaintext: jsonEncode(request),
        recipientPubkey: connection.remotePubkey,
      );

      final requestEvent = Nip01Event(
        pubkey: localSigner.publicKey,
        kind: BunkerRequest.kKind,
        tags: [
          ["p", connection.remotePubkey],
        ],
        content: encryptedRequest,
      );

      final signedEvent = await localSigner.sign(requestEvent);
      // not awaiting the broadcast: the slowest relay's OK would delay a
      // response already received through a faster one
      relayPublishes.publish(signedEvent, relays: connection.relays);

      // holds the slot until the bunker answers
      await entry.completer.future;
    }).catchError((Object error, StackTrace stackTrace) {
      if (entry.completer.isCompleted) return;
      _requests.remove(request.id);
      if (pending != null) _notifyPendingRequestsChange();
      entry.completer.completeError(error, stackTrace);
    });

    return entry.completer.future;
  }

  @override
  bool get canSign {
    return true;
  }

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) {
    final request = BunkerRequest(
      method: 'nip04_decrypt',
      params: [senderPubkey, ciphertext],
    );
    return _send(
      request,
      pending: PendingDecryptRequest.nip04(
        id: request.id,
        createdAt: DateTime.now(),
        signerPubkey: _publicKey,
        ciphertext: ciphertext,
        senderPubkey: senderPubkey,
      ),
    );
  }

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) {
    final request = BunkerRequest(
      method: 'nip44_decrypt',
      params: [senderPubkey, ciphertext],
    );
    return _send(
      request,
      pending: PendingDecryptRequest.nip44(
        id: request.id,
        createdAt: DateTime.now(),
        signerPubkey: _publicKey,
        ciphertext: ciphertext,
        senderPubkey: senderPubkey,
      ),
    );
  }

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) {
    final request = BunkerRequest(
      method: 'nip04_encrypt',
      params: [recipientPubkey, plaintext],
    );
    return _send(
      request,
      pending: PendingEncryptRequest.nip04(
        id: request.id,
        createdAt: DateTime.now(),
        signerPubkey: _publicKey,
        plaintext: plaintext,
        recipientPubkey: recipientPubkey,
      ),
    );
  }

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) {
    final request = BunkerRequest(
      method: 'nip44_encrypt',
      params: [recipientPubkey, plaintext],
    );
    return _send(
      request,
      pending: PendingEncryptRequest.nip44(
        id: request.id,
        createdAt: DateTime.now(),
        signerPubkey: _publicKey,
        plaintext: plaintext,
        recipientPubkey: recipientPubkey,
      ),
    );
  }

  @override
  String get publicKey => _publicKey;

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    if (event.pubkey != _publicKey) {
      throw ArgumentError.value(
        event.pubkey,
        'event.pubkey',
        'is not the pubkey of the signer, $_publicKey',
      );
    }

    final eventMap = {
      "kind": event.kind,
      "content": event.content,
      "tags": event.tags,
      "created_at": event.createdAt,
    };
    final request = BunkerRequest(
      method: 'sign_event',
      params: [jsonEncode(eventMap)],
    );

    final signedEventJson = await _send(
      request,
      pending: PendingSignRequest(
        id: request.id,
        createdAt: DateTime.now(),
        signerPubkey: _publicKey,
        event: event,
      ),
    );

    final signedEvent = _tryParseEvent(signedEventJson);
    if (signedEvent == null ||
        signedEvent.sig == null ||
        !signedEvent.hasValidId) {
      throw SignerRequestFailedException(
        'The bunker returned an invalid event',
        requestId: request.id,
        cause: signedEventJson,
      );
    }
    if (signedEvent.pubkey != _publicKey) {
      throw SignerRequestFailedException(
        'The bunker signed as ${signedEvent.pubkey} instead of $_publicKey',
        requestId: request.id,
      );
    }
    return signedEvent;
  }

  static Nip01Event? _tryParseEvent(String json) {
    try {
      return Nip01Event.tryFromJson(jsonDecode(json));
    } on FormatException {
      return null;
    }
  }

  Future<String> ping() => _send(BunkerRequest(method: 'ping'));

  /// Returns the relays the remote signer moved to, or null if it keeps the
  /// current ones.
  Future<List<RelayUrl>?> switchRelays() async {
    final response = await _send(BunkerRequest(method: 'switch_relays'));

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
  List<PendingSignerRequest> get pendingRequests => [
    for (final request in _requests.values) ?request.pending,
  ];

  @override
  bool cancelRequest(String requestId) {
    final entry = _requests[requestId];
    if (entry == null || entry.pending == null) return false;

    _requests.remove(requestId);
    entry.completer.completeError(SignerRequestCancelledException(requestId));
    _notifyPendingRequestsChange();
    return true;
  }

  @override
  Future<void> dispose() async {
    cancelAllQueued();
    await subscription?.close();
    await _pendingRequestsController.close();
  }
}
