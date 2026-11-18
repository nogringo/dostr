import 'dart:async';
import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:rxdart/rxdart.dart';

import 'bounded_lru_set.dart';
import 'bunker_connection.dart';
import 'bunker_request.dart';
import 'nip46_message.dart';

class _RemoteRequest {
  final completer = Completer<String>();

  /// null for a request the user does not approve, such as a ping
  final PendingSignerRequest? pending;

  _RemoteRequest(this.pending);
}

class Nip46Signer with ConcurrencyLimiterMixin implements NostrSigner {
  BunkerConnection _connection;
  final RelayReqs _relayReqs;
  final RelayPublishes _relayPublishes;
  final NostrSigner _localSigner;

  /// Gets the url of an auth challenge, where the user approves a request.
  void Function(String url)? authCallback;

  /// When set, [sign] checks the signature of every event the remote signer
  /// signs, and fails on an invalid one.
  final EventVerifier? verifier;

  RelayReq? _subscription;

  // every relay of the bunker delivers each response
  final BoundedLruSet<String> _seenResponseIds = BoundedLruSet(maxSize: 1000);

  final _requests = <String, _RemoteRequest>{};
  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  late final String _publicKey;

  @override
  final int maxConcurrentRequests;

  /// Default bunker concurrency. NIP-46 round-trips through a relay, so the
  /// limit guards against flooding it with thousands of pending events.
  /// Lower this if you hit relay rate limits.
  static const int defaultMaxConcurrentRequests = 100;

  /// How long connecting waits for the remote signer, which may ask the user
  /// to approve first.
  static const Duration defaultConnectTimeout = Duration(minutes: 10);

  /// A signer for the user [publicKey] of the bunker behind [connection], such
  /// as an account restored from storage. [connect] asks the bunker for it.
  Nip46Signer({
    required BunkerConnection connection,
    required String publicKey,
    required RelayReqs relayReqs,
    required RelayPublishes relayPublishes,
    void Function(String url)? authCallback,
    EventVerifier? verifier,
    required LocalSignerFactory signerFactory,
    int maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) : this._(
         connection: connection,
         publicKey: publicKey,
         relayReqs: relayReqs,
         relayPublishes: relayPublishes,
         authCallback: authCallback,
         verifier: verifier,
         signerFactory: signerFactory,
         maxConcurrentRequests: maxConcurrentRequests,
       );

  Nip46Signer._({
    required BunkerConnection connection,
    required String? publicKey,
    required RelayReqs relayReqs,
    required RelayPublishes relayPublishes,
    required this.authCallback,
    required this.verifier,
    required LocalSignerFactory signerFactory,
    required this.maxConcurrentRequests,
  }) : _connection = connection,
       _relayReqs = relayReqs,
       _relayPublishes = relayPublishes,
       _localSigner = signerFactory.create(connection.privateKey),
       assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0') {
    if (publicKey != null) _publicKey = publicKey;
    _listen();
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
    void Function(String url)? authCallback,
    EventVerifier? verifier,
    required LocalSignerFactory signerFactory,
    int maxConcurrentRequests = defaultMaxConcurrentRequests,
    Duration timeout = defaultConnectTimeout,
  }) async {
    final signer = Nip46Signer._(
      connection: connection,
      publicKey: null,
      relayReqs: relayReqs,
      relayPublishes: relayPublishes,
      authCallback: authCallback,
      verifier: verifier,
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

  /// The bunker and its relays. [switchRelays] may replace it, so store it
  /// again after.
  BunkerConnection get connection => _connection;

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

  void _listen() {
    final filter = Filter(
      authors: [_connection.remotePubkey],
      kinds: [BunkerRequest.kKind],
      pTags: [_localSigner.publicKey],
    );
    final subscription = _subscription = _relayReqs.req(
      relays: {
        for (final relay in _connection.relays) relay: [filter],
      },
      closeOnEose: false,
    );

    subscription.events
        .map((received) => received.event)
        .where((event) => _seenResponseIds.add(event.id))
        .listen(_onEvent);
  }

  Future<void> _onEvent(Nip01Event event) async {
    final message = await readMessage(_localSigner, event);
    if (message == null) return;

    final error = message['error'];
    if (message['result'] == 'auth_url') {
      if (error is String) authCallback?.call(error);
      return;
    }

    final id = message['id'];
    if (id is! String) return;
    final entry = _requests.remove(id);
    if (entry == null) return;
    if (entry.pending != null) _notifyPendingRequestsChange();

    if (error != null) {
      entry.completer.completeError(
        SignerRequestRejectedException(
          requestId: id,
          originalMessage: '$error',
        ),
      );
    } else {
      final result = message['result'];
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
      final signedEvent = await signedRequestEvent(
        _localSigner,
        request,
        remotePubkey: _connection.remotePubkey,
      );
      // cancelled or disposed meanwhile: don't broadcast what nobody waits for
      if (!_requests.containsKey(request.id)) return;
      // not awaiting the broadcast: the slowest relay's OK would delay a
      // response already received through a faster one
      _relayPublishes.publish(signedEvent, relays: _connection.relays);

      // holds the slot until the bunker answers
      await entry.completer.future;
    }).catchError(
      (Object error, StackTrace stackTrace) =>
          _fail(request.id, error, stackTrace),
    );

    return entry.completer.future;
  }

  /// Fails [requestId] with [error], unless it already completed.
  void _fail(String requestId, Object error, [StackTrace? stackTrace]) {
    final entry = _requests.remove(requestId);
    if (entry == null) return;
    if (entry.pending != null) _notifyPendingRequestsChange();
    entry.completer.completeError(error, stackTrace);
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
    final verifier = this.verifier;
    if (verifier != null && !await verifier.verify(signedEvent)) {
      throw SignerRequestFailedException(
        'The bunker returned an invalid signature',
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
        ? decoded.whereType<String>().map(RelayUrl.tryParse).nonNulls.toList()
        : const <RelayUrl>[];
    if (relays.isEmpty) return null;

    final previousSubscription = _subscription;
    _connection = BunkerConnection(
      privateKey: _connection.privateKey,
      remotePubkey: _connection.remotePubkey,
      relays: relays,
    );
    _listen();
    await previousSubscription?.close();

    return relays;
  }

  Future<bool>? _logout;

  /// Ends the session on the bunker, then disposes this signer.
  ///
  /// Returns whether the bunker acknowledged within [timeout]. A [dispose]
  /// meanwhile waits for it, so the bunker still gets it. Delete the stored
  /// [connection] either way: NIP-46 makes `logout` a courtesy, and the
  /// bunker may still accept requests from its private key.
  Future<bool> logout({Duration timeout = const Duration(seconds: 10)}) =>
      _logout ??= _sendLogout(timeout);

  Future<bool> _sendLogout(Duration timeout) async {
    try {
      final result = await _send(
        BunkerRequest(method: 'logout'),
      ).timeout(timeout);
      return result == 'ack';
    } on SignerRequestException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      await _close();
    }
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
    if (_requests[requestId]?.pending == null) return false;

    _fail(requestId, SignerRequestCancelledException(requestId));
    return true;
  }

  @override
  Future<void> dispose() async {
    await _logout?.catchError((_) => false);
    await _close();
  }

  Future<void> _close() async {
    // the subscription closes, so no answer can come for them anymore
    for (final requestId in _requests.keys.toList()) {
      _fail(
        requestId,
        SignerRequestFailedException(
          'The signer was disposed before the bunker answered',
          requestId: requestId,
        ),
      );
    }
    cancelAllQueued();
    await _subscription?.close();
    await _pendingRequestsController.close();
  }
}
