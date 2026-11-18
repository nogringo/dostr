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
  _PendingRequestEntry(this.completer, this.request);
}

/// Signer backed by a NIP-55 external signer application.
///
/// NIP-55 is a protocol implemented by several external signer apps.
/// This signer delegates all cryptographic
/// operations to whichever compatible signer is installed via [Nip55SignerApp].
class Nip55Signer with ConcurrencyLimiterMixin implements NostrSigner {
  final Nip55SignerApp signerApp;

  /// in hex, also when the signer was given an npub
  @override
  final String publicKey;

  final _pendingRequests = <String, _PendingRequestEntry>{};
  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  int _requestCounter = 0;

  @override
  final int maxConcurrentRequests;

  /// Default external-signer concurrency. Lower this if you target a flow that
  /// prompts the user via Android intents for every request.
  static const int defaultMaxConcurrentRequests = 100;

  /// get a NIP-55 external signer for [publicKey], in hex or as an npub
  Nip55Signer({
    required String publicKey,
    required this.signerApp,
    this.maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) : publicKey = publicKey.startsWith(Npub.prefix)
           ? Npub.decode(publicKey).pubkey
           : publicKey,
       assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0');

  /// The signer app answers a refusal with no result (NIP-55).
  static String _extractResult(Map<dynamic, dynamic> map, String requestId) {
    final result = map['signature'] as String?;
    if (result == null || result.isEmpty) {
      throw SignerRequestRejectedException(requestId: requestId);
    }
    return result;
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

  /// Runs [operation] while [describe] waits in [pendingRequests]. An error of
  /// the signer app means it turned the request down.
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
          if (!_pendingRequests.containsKey(requestId)) {
            throw SignerRequestCancelledException(requestId);
          }
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
                  : SignerRequestRejectedException(
                      requestId: requestId,
                      originalMessage: error.toString(),
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
        if (signedEventJson == null || signedEventJson.isEmpty) {
          return toSign.copyWith(sig: signature);
        }
        return _checkSigned(signedEventJson, requestId);
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

  @override
  bool get canSign => true;

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
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
    await _pendingRequestsController.close();
  }
}
