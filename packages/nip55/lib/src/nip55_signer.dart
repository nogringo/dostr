import 'dart:async';
import 'dart:convert';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import 'nip55_signer_app.dart';

/// Internal class to track a pending request with its completer
class _PendingRequestEntry {
  final Completer<dynamic> completer;
  final PendingSignerRequest request;
  bool sentToSignerApp = false;
  _PendingRequestEntry(this.completer, this.request);
}

/// Signer backed by a NIP-55 external signer application.
///
/// NIP-55 is a protocol implemented by several external signer apps.
/// This signer delegates all cryptographic
/// operations to whichever compatible signer is installed via [Nip55SignerApp].
class Nip55Signer with ConcurrencyLimiterMixin implements NostrSigner {
  final Nip55SignerApp signerApp;

  /// When set, [sign] checks the signature of every event the signer app
  /// signs, and fails on an invalid one.
  final EventVerifier? verifier;

  /// in hex, also when the signer was given an npub
  @override
  final String publicKey;

  final _pendingRequests = <String, _PendingRequestEntry>{};
  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  // shared by every signer: the plugin matches answers and cancellations by id
  static int _requestCounter = 0;

  @override
  final int maxConcurrentRequests;

  /// Default external-signer concurrency. Lower this if you target a flow that
  /// prompts the user via Android intents for every request.
  static const int defaultMaxConcurrentRequests = 100;

  /// get a NIP-55 external signer for [publicKey], in hex or as an npub
  Nip55Signer({
    required String publicKey,
    required this.signerApp,
    this.verifier,
    this.maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) : publicKey = publicKey.startsWith(Npub.prefix)
           ? Npub.decode(publicKey).pubkey
           : publicKey,
       assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0');

  static String _extractResult(Map<dynamic, dynamic> map, String requestId) {
    if (map['rejected'] == 'true') {
      throw SignerRequestRejectedException(requestId: requestId);
    }
    final result = map['signature'] as String?;
    if (result == null || result.isEmpty) {
      throw SignerRequestFailedException(
        'The signer app returned no result',
        requestId: requestId,
      );
    }
    return result;
  }

  void _checkSupported() {
    if (!canSign) {
      throw UnsupportedError('NIP-55 is only available on Android');
    }
  }

  String _generateRequestId() {
    return 'nip55_${DateTime.now().millisecondsSinceEpoch}_${_requestCounter++}';
  }

  void _notifyPendingRequestsChange() {
    if (_pendingRequestsController.isClosed) return;
    _pendingRequestsController.add(
      _pendingRequests.values.map((e) => e.request).toList(),
    );
  }

  /// Runs [operation] while [describe] waits in [pendingRequests].
  Future<T> _trackRequest<T>(
    PendingSignerRequest Function(String requestId) describe,
    Future<T> Function(String requestId) operation,
  ) {
    final requestId = _generateRequestId();
    final completer = Completer<T>();

    _pendingRequests[requestId] = _PendingRequestEntry(
      completer as Completer<dynamic>,
      describe(requestId),
    );
    _notifyPendingRequestsChange();

    // Throttle the actual call to the signer; queued requests still appear in
    // `pendingRequests` so the UI sees the full backlog. If the request was
    // cancelled while queued, skip the signer call entirely.
    runThrottled(() async {
          final entry = _pendingRequests[requestId];
          if (entry == null) {
            throw SignerRequestCancelledException(requestId);
          }
          entry.sentToSignerApp = true;
          return await operation(requestId);
        })
        .then((result) {
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        })
        .catchError((error) {
          if (!completer.isCompleted) {
            completer.completeError(
              error is SignerRequestException
                  ? error
                  : SignerRequestFailedException(
                      'The request to the signer app failed',
                      requestId: requestId,
                      cause: error,
                    ),
            );
          }
        })
        .whenComplete(() {
          _pendingRequests.remove(requestId);
          _notifyPendingRequestsChange();
        });

    return completer.future;
  }

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    _checkSupported();
    if (event.pubkey != publicKey) {
      throw ArgumentError.value(
        event.pubkey,
        'event.pubkey',
        'is not the pubkey of the signer, $publicKey',
      );
    }
    final toSign = event.copyWith(id: event.payloadId);

    return _trackRequest(
      (id) => PendingSignRequest(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        event: toSign,
      ),
      (requestId) async {
        final map = await signerApp.signEvent(
          currentUser: publicKey,
          eventJson: toSign.toJsonString(),
          id: requestId,
        );
        final signature = _extractResult(map, requestId);

        // Prefer the event the signer actually signed, when it returns one.
        final signedEventJson = map['event'] as String?;
        final signed = signedEventJson == null || signedEventJson.isEmpty
            ? toSign.copyWith(sig: signature)
            : _checkSigned(signedEventJson, requestId);
        final verifier = this.verifier;
        if (verifier != null && !await verifier.verify(signed)) {
          throw SignerRequestFailedException(
            'The signer app returned an invalid signature',
            requestId: requestId,
          );
        }
        return signed;
      },
    );
  }

  Nip01Event _checkSigned(String json, String requestId) {
    Nip01Event? signed;
    try {
      signed = Nip01Event.tryFromJson(jsonDecode(json));
    } on FormatException {
      signed = null;
    }
    if (signed == null || signed.sig == null || !signed.hasValidId) {
      throw SignerRequestFailedException(
        'The signer app returned an invalid event',
        requestId: requestId,
        cause: json,
      );
    }
    if (signed.pubkey != publicKey) {
      throw SignerRequestFailedException(
        'The signer app signed as ${signed.pubkey} instead of $publicKey',
        requestId: requestId,
      );
    }
    return signed;
  }

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    _checkSupported();
    return _trackRequest(
      (id) => PendingDecryptRequest.nip04(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        ciphertext: ciphertext,
        senderPubkey: senderPubkey,
      ),
      (requestId) async {
        final map = await signerApp.nip04Decrypt(
          ciphertext: ciphertext,
          currentUser: publicKey,
          pubkey: senderPubkey,
          id: requestId,
        );
        return _extractResult(map, requestId);
      },
    );
  }

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    _checkSupported();
    return _trackRequest(
      (id) => PendingEncryptRequest.nip04(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        plaintext: plaintext,
        recipientPubkey: recipientPubkey,
      ),
      (requestId) async {
        final map = await signerApp.nip04Encrypt(
          plaintext: plaintext,
          currentUser: publicKey,
          pubkey: recipientPubkey,
          id: requestId,
        );
        return _extractResult(map, requestId);
      },
    );
  }

  /// false off Android, where every request throws an [UnsupportedError]
  @override
  bool get canSign => signerApp.isAvailable;

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    _checkSupported();
    return _trackRequest(
      (id) => PendingEncryptRequest.nip44(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        plaintext: plaintext,
        recipientPubkey: recipientPubkey,
      ),
      (requestId) async {
        final map = await signerApp.nip44Encrypt(
          plaintext: plaintext,
          currentUser: publicKey,
          pubkey: recipientPubkey,
          id: requestId,
        );
        return _extractResult(map, requestId);
      },
    );
  }

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    _checkSupported();
    return _trackRequest(
      (id) => PendingDecryptRequest.nip44(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        ciphertext: ciphertext,
        senderPubkey: senderPubkey,
      ),
      (requestId) async {
        final map = await signerApp.nip44Decrypt(
          ciphertext: ciphertext,
          currentUser: publicKey,
          pubkey: senderPubkey,
          id: requestId,
        );
        return _extractResult(map, requestId);
      },
    );
  }

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      _pendingRequestsController.stream;

  @override
  List<PendingSignerRequest> get pendingRequests =>
      _pendingRequests.values.map((e) => e.request).toList();

  @override
  bool cancelRequest(String requestId) =>
      _drop(requestId, SignerRequestCancelledException(requestId));

  bool _drop(String requestId, SignerRequestException error) {
    final entry = _pendingRequests.remove(requestId);
    if (entry == null) return false;
    entry.completer.completeError(error);
    _notifyPendingRequestsChange();
    if (entry.sentToSignerApp) {
      // frees the slot of the request, which waits for the signer app
      signerApp.cancelRequest(requestId).ignore();
    }
    return true;
  }

  @override
  Future<void> dispose() async {
    final sent = [
      for (final MapEntry(key: requestId, value: entry)
          in _pendingRequests.entries)
        if (entry.sentToSignerApp) requestId,
    ];
    for (final requestId in sent) {
      _drop(
        requestId,
        SignerRequestFailedException(
          'The signer was disposed before the signer app answered',
          requestId: requestId,
        ),
      );
    }
    cancelAllQueued();
    await _pendingRequestsController.close();
  }
}
