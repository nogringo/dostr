import 'dart:async';
import 'dart:js_interop';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import 'nip07_js_interop.dart' as js;

class _PendingRequestEntry {
  final Completer<dynamic> completer;
  final PendingSignerRequest request;
  bool sentToExtension = false;

  _PendingRequestEntry(this.completer, this.request);
}

class Nip07Signer with ConcurrencyLimiterMixin implements NostrSigner {
  /// the pubkey of the extension account this signer signs as
  @override
  final String publicKey;

  final _pendingRequests = <String, _PendingRequestEntry>{};
  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  // shared by every signer, so request ids stay unique across them
  static int _requestCounter = 0;

  @override
  final int maxConcurrentRequests;

  static const int defaultMaxConcurrentRequests = 100;

  /// A signer for the extension account [publicKey], such as one restored
  /// from storage. [connect] asks the extension for it.
  Nip07Signer({
    required this.publicKey,
    this.maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) : assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0');

  /// Whether the browser has a NIP-07 extension, in `window.nostr`.
  static bool get isAvailable => js.nostr != null;

  /// Asks the extension for the user's pubkey, which it may ask the user to
  /// approve first, and completes with a signer for it.
  ///
  /// Throws a [StateError] without an extension, see [isAvailable], and a
  /// [SignerRequestRejectedException] when the extension refuses.
  static Future<Nip07Signer> connect({
    int maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) async {
    final nostr = _extension();
    final publicKey = (await _ask(() => nostr.getPublicKey())).dartify();
    if (publicKey is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(publicKey)) {
      throw SignerRequestFailedException(
        'The extension sent an invalid pubkey',
        cause: publicKey,
      );
    }
    return Nip07Signer(
      publicKey: publicKey,
      maxConcurrentRequests: maxConcurrentRequests,
    );
  }

  static js.Nostr _extension() =>
      js.nostr ?? (throw StateError('No NIP-07 extension in window.nostr'));

  /// The answer of the extension. It turns a request down by rejecting it.
  static Future<JSAny?> _ask(
    JSPromise<JSAny?> Function() request, {
    String? requestId,
  }) async {
    try {
      return await request().toDart;
    } catch (error) {
      throw SignerRequestRejectedException(
        requestId: requestId,
        originalMessage: error.toString(),
      );
    }
  }

  static Future<String> _askText(
    JSPromise<JSAny?> Function() request,
    String requestId,
  ) async {
    final text = (await _ask(request, requestId: requestId)).dartify();
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
      (requestId) => _askText(
        () => nip04.decrypt(senderPubkey.toJS, ciphertext.toJS),
        requestId,
      ),
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
      (requestId) => _askText(
        () => nip44.decrypt(senderPubkey.toJS, ciphertext.toJS),
        requestId,
      ),
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
      (requestId) => _askText(
        () => nip04.encrypt(recipientPubkey.toJS, plaintext.toJS),
        requestId,
      ),
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
      (requestId) => _askText(
        () => nip44.encrypt(recipientPubkey.toJS, plaintext.toJS),
        requestId,
      ),
    );
  }

  static T _scheme<T>(T? scheme, String name) =>
      scheme ??
      (throw SignerRequestFailedException('The extension has no $name'));

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    final nostr = _extension();
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
        final jsEvent = js.NostrEvent()
          ..pubkey = event.pubkey
          ..createdAt = event.createdAt
          ..kind = event.kind
          ..content = event.content
          ..tags = event.tags
              .map((tag) => tag.map((item) => item.toJS).toList().toJS)
              .toList()
              .toJS;

        final answer = await _ask(
          () => nostr.signEvent(jsEvent),
          requestId: requestId,
        );
        final signed = answer.isA<JSObject>() ? answer as js.NostrEvent : null;
        final id = signed?.id;
        final sig = signed?.sig;
        final signedEvent = signed == null || id == null || sig == null
            ? null
            : event.copyWith(
                id: id,
                sig: sig,
                pubkey: signed.pubkey,
                createdAt: signed.createdAt,
                kind: signed.kind,
                content: signed.content,
                tags: signed.tagsList,
              );
        if (signedEvent == null || !signedEvent.hasValidId) {
          throw SignerRequestFailedException(
            'The extension returned an invalid event',
            requestId: requestId,
          );
        }
        if (signedEvent.pubkey != publicKey) {
          throw SignerRequestFailedException(
            'The extension signed as ${signedEvent.pubkey} instead of '
            '$publicKey',
            requestId: requestId,
          );
        }
        return signedEvent;
      },
    );
  }

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
