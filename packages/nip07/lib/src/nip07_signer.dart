import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip01/hex.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import 'nip07_extension.dart';
import 'nip07_extension_stub.dart'
    if (dart.library.js_interop) 'nip07_extension_web.dart';

/// The extension in `window.nostr`, null without one. Tests swap it for a
/// fake.
Nip07Extension? Function() findNip07Extension = windowNostr;

class _PendingRequestEntry {
  final Completer<dynamic> completer;
  final PendingSignerRequest request;
  bool sentToExtension = false;

  _PendingRequestEntry(this.completer, this.request);
}

/// Signs and encrypts with the user's NIP-07 browser extension, through
/// `window.nostr`.
///
/// The extension asks the user to approve each request. It turns a request
/// down, or fails it, by rejecting it, and NIP-07 does not tell the two apart:
/// both throw a [SignerRequestRejectedException].
///
/// Outside a browser, [isAvailable] and [canSign] are false and every request
/// throws an [UnsupportedError].
class Nip07Signer with ConcurrencyLimiterMixin implements NostrSigner {
  /// the pubkey of the extension account this signer signs as
  @override
  final String publicKey;

  /// When set, [sign] checks the signature of every event the extension
  /// signs, and fails on an invalid one.
  final EventVerifier? verifier;

  final _pendingRequests = <String, _PendingRequestEntry>{};
  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  // shared by every signer, so request ids stay unique across them
  static int _requestCounter = 0;

  @override
  final int maxConcurrentRequests;

  static const int defaultMaxConcurrentRequests = 100;

  static const Duration defaultPublicKeyTimeout = Duration(minutes: 10);

  /// A signer for the extension account [publicKey], such as one restored
  /// from storage. [connect] asks the extension for it.
  ///
  /// Throws a [FormatException] when [publicKey] is not 64 lowercase hex
  /// characters.
  Nip07Signer({
    required String publicKey,
    this.verifier,
    this.maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) : publicKey = isLowercaseHex(publicKey, length: 64)
           ? publicKey
           : throw FormatException('Not a valid public key', publicKey),
       assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0');

  /// Whether the browser has a NIP-07 extension, in `window.nostr`.
  ///
  /// An extension may add it a moment after the page loads, so read it once
  /// the app runs, or use [waitForExtension].
  static bool get isAvailable => findNip07Extension() != null;

  /// Whether the browser has a NIP-07 extension, waiting up to [timeout] for
  /// one that adds `window.nostr` after the page loads.
  ///
  /// Completes with false at once outside a browser.
  static Future<bool> waitForExtension({
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final waited = Stopwatch()..start();
    while (!isAvailable) {
      if (!supportsNip07 || waited.elapsed >= timeout) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  /// Asks the extension for the user's pubkey, which it may ask the user to
  /// approve first, and completes with a signer for it.
  ///
  /// Throws a [StateError] without an extension, see [isAvailable], a
  /// [SignerRequestRejectedException] when the extension refuses, and a
  /// [SignerRequestFailedException] when no valid pubkey came within
  /// [timeout].
  static Future<Nip07Signer> connect({
    EventVerifier? verifier,
    int maxConcurrentRequests = defaultMaxConcurrentRequests,
    Duration timeout = defaultPublicKeyTimeout,
  }) async {
    final extension = _extension();
    final Object? publicKey;
    try {
      publicKey = await _ask(extension.getPublicKey).timeout(timeout);
    } on TimeoutException {
      throw SignerRequestFailedException(
        'The extension sent no pubkey within $timeout',
      );
    }
    if (publicKey is! String || !isLowercaseHex(publicKey, length: 64)) {
      throw SignerRequestFailedException(
        'The extension sent an invalid pubkey',
        cause: publicKey,
      );
    }
    return Nip07Signer(
      publicKey: publicKey,
      verifier: verifier,
      maxConcurrentRequests: maxConcurrentRequests,
    );
  }

  static Nip07Extension _extension() =>
      findNip07Extension() ??
      (throw supportsNip07
          ? StateError('No NIP-07 extension in window.nostr')
          : UnsupportedError('NIP-07 is not available on this platform'));

  /// The answer of the extension. It turns a request down by rejecting it.
  static Future<Object?> _ask(
    Future<Object?> Function() request, {
    String? requestId,
  }) async {
    try {
      return await request();
    } catch (error) {
      throw SignerRequestRejectedException(
        requestId: requestId,
        originalMessage: error.toString(),
      );
    }
  }

  static Future<String> _askText(
    Future<Object?> Function() request,
    String requestId,
  ) async {
    final text = await _ask(request, requestId: requestId);
    if (text is! String) {
      throw SignerRequestFailedException(
        'The extension sent no text',
        requestId: requestId,
        cause: text,
      );
    }
    return text;
  }

  String _generateRequestId() {
    return 'nip07_${DateTime.now().millisecondsSinceEpoch}_${_requestCounter++}';
  }

  void _notifyPendingRequestsChange() {
    if (_pendingRequestsController.isClosed) return;
    _pendingRequestsController.add(
      _pendingRequests.values.map((entry) => entry.request).toList(),
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

    runThrottled(() async {
          final entry = _pendingRequests[requestId];
          if (entry == null) {
            throw SignerRequestCancelledException(requestId);
          }
          entry.sentToExtension = true;
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
                      'The extension sent an answer the signer cannot use',
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
  bool get canSign => isAvailable;

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    final nip04 = _scheme(_extension().nip04, 'NIP-04');
    return _trackRequest(
      (id) => PendingDecryptRequest.nip04(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        ciphertext: ciphertext,
        senderPubkey: senderPubkey,
      ),
      (requestId) =>
          _askText(() => nip04.decrypt(senderPubkey, ciphertext), requestId),
    );
  }

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    final nip44 = _scheme(_extension().nip44, 'NIP-44');
    return _trackRequest(
      (id) => PendingDecryptRequest.nip44(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        ciphertext: ciphertext,
        senderPubkey: senderPubkey,
      ),
      (requestId) =>
          _askText(() => nip44.decrypt(senderPubkey, ciphertext), requestId),
    );
  }

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    final nip04 = _scheme(_extension().nip04, 'NIP-04');
    return _trackRequest(
      (id) => PendingEncryptRequest.nip04(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        plaintext: plaintext,
        recipientPubkey: recipientPubkey,
      ),
      (requestId) =>
          _askText(() => nip04.encrypt(recipientPubkey, plaintext), requestId),
    );
  }

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    final nip44 = _scheme(_extension().nip44, 'NIP-44');
    return _trackRequest(
      (id) => PendingEncryptRequest.nip44(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        plaintext: plaintext,
        recipientPubkey: recipientPubkey,
      ),
      (requestId) =>
          _askText(() => nip44.encrypt(recipientPubkey, plaintext), requestId),
    );
  }

  static Nip07Cipher _scheme(Nip07Cipher? scheme, String name) =>
      scheme ??
      (throw SignerRequestFailedException('The extension has no $name'));

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    final extension = _extension();
    if (event.pubkey != publicKey) {
      throw ArgumentError.value(
        event.pubkey,
        'event.pubkey',
        'is not the pubkey of the signer, $publicKey',
      );
    }

    return _trackRequest(
      (id) => PendingSignRequest(
        id: id,
        createdAt: DateTime.now(),
        signerPubkey: publicKey,
        event: event,
      ),
      (requestId) async {
        final answer = await _ask(
          () => extension.signEvent({
            'pubkey': event.pubkey,
            'created_at': event.createdAt,
            'kind': event.kind,
            'tags': event.tags,
            'content': event.content,
          }),
          requestId: requestId,
        );
        final signed = _readEvent(answer);
        if (signed == null || signed.sig == null || !signed.hasValidId) {
          throw SignerRequestFailedException(
            'The extension returned an invalid event',
            requestId: requestId,
            cause: answer,
          );
        }
        if (signed.pubkey != publicKey) {
          throw SignerRequestFailedException(
            'The extension signed as ${signed.pubkey} instead of $publicKey',
            requestId: requestId,
          );
        }
        final verifier = this.verifier;
        if (verifier != null && !await verifier.verify(signed)) {
          throw SignerRequestFailedException(
            'The extension returned an invalid signature',
            requestId: requestId,
          );
        }
        return signed;
      },
    );
  }

  // dart2wasm turns every JS number into a double
  static Nip01Event? _readEvent(Object? answer) => answer is Map
      ? Nip01Event.tryFromJson({
          ...answer,
          'created_at': _integer(answer['created_at']),
          'kind': _integer(answer['kind']),
        })
      : null;

  static Object? _integer(Object? value) =>
      value is double && value.isFinite && value == value.truncateToDouble()
      ? value.toInt()
      : value;

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      _pendingRequestsController.stream;

  @override
  List<PendingSignerRequest> get pendingRequests =>
      _pendingRequests.values.map((entry) => entry.request).toList();

  @override
  bool cancelRequest(String requestId) =>
      _drop(requestId, SignerRequestCancelledException(requestId));

  bool _drop(String requestId, SignerRequestException error) {
    final entry = _pendingRequests.remove(requestId);
    if (entry == null) return false;
    entry.completer.completeError(error);
    _notifyPendingRequestsChange();
    return true;
  }

  @override
  Future<void> dispose() async {
    final sent = [
      for (final MapEntry(key: requestId, value: entry)
          in _pendingRequests.entries)
        if (entry.sentToExtension) requestId,
    ];
    for (final requestId in sent) {
      _drop(
        requestId,
        SignerRequestFailedException(
          'The signer was disposed before the extension answered',
          requestId: requestId,
        ),
      );
    }
    cancelAllQueued();
    await _pendingRequestsController.close();
  }
}
