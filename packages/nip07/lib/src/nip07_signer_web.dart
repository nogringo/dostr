import 'dart:async';
import 'dart:js_interop';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import 'nip07_js_interop.dart' as js;

class _PendingRequestEntry {
  final Completer<dynamic> completer;
  final PendingSignerRequest request;

  _PendingRequestEntry(this.completer, this.request);
}

class Nip07Signer with ConcurrencyLimiterMixin implements NostrSigner {
  String? cachedPublicKey;

  final _pendingRequests = <String, _PendingRequestEntry>{};
  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  int _requestCounter = 0;

  @override
  final int maxConcurrentRequests;

  static const int defaultMaxConcurrentRequests = 100;

  Nip07Signer({
    this.cachedPublicKey,
    this.maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) : assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0');

  String _generateRequestId() {
    return 'nip07_${DateTime.now().millisecondsSinceEpoch}_${_requestCounter++}';
  }

  void _notifyPendingRequestsChange() {
    _pendingRequestsController.add(
      _pendingRequests.values.map((entry) => entry.request).toList(),
    );
  }

  Future<T> _trackRequest<T>(
    SignerMethod method,
    Future<T> Function() operation, {
    Nip01Event? event,
    String? plaintext,
    String? ciphertext,
    String? counterpartyPubkey,
  }) {
    final requestId = _generateRequestId();
    final completer = Completer<T>();
    final pendingRequest = PendingSignerRequest(
      id: requestId,
      method: method,
      createdAt: DateTime.now(),
      signerPubkey: cachedPublicKey ?? '',
      event: event,
      plaintext: plaintext,
      ciphertext: ciphertext,
      counterpartyPubkey: counterpartyPubkey,
    );

    _pendingRequests[requestId] = _PendingRequestEntry(
      completer as Completer<dynamic>,
      pendingRequest,
    );
    _notifyPendingRequestsChange();

    runThrottled(() async {
          if (!_pendingRequests.containsKey(requestId)) {
            throw SignerRequestCancelledException(requestId);
          }
          return operation();
        })
        .then((result) {
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        })
        .catchError((error) {
          if (!completer.isCompleted) {
            completer.completeError(
              SignerRequestRejectedException(
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
  bool get canSign {
    return js.nostr != null;
  }

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    if (js.nostr == null) {
      throw Exception('NIP-07 extension not available');
    }

    return _trackRequest(
      SignerMethod.nip04Decrypt,
      () async {
        final result = await js.nostr!.nip04!
            .decrypt(senderPubkey.toJS, ciphertext.toJS)
            .toDart;
        return result.toDart;
      },
      ciphertext: ciphertext,
      counterpartyPubkey: senderPubkey,
    );
  }

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    if (js.nostr == null) {
      throw Exception('NIP-07 extension not available');
    }

    return _trackRequest(
      SignerMethod.nip44Decrypt,
      () async {
        final result = await js.nostr!.nip44!
            .decrypt(senderPubkey.toJS, ciphertext.toJS)
            .toDart;
        return result.toDart;
      },
      ciphertext: ciphertext,
      counterpartyPubkey: senderPubkey,
    );
  }

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    if (js.nostr == null) {
      throw Exception('NIP-07 extension not available');
    }

    return _trackRequest(
      SignerMethod.nip04Encrypt,
      () async {
        final result = await js.nostr!.nip04!
            .encrypt(recipientPubkey.toJS, plaintext.toJS)
            .toDart;
        return result.toDart;
      },
      plaintext: plaintext,
      counterpartyPubkey: recipientPubkey,
    );
  }

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    if (js.nostr == null) {
      throw Exception('NIP-07 extension not available');
    }

    return _trackRequest(
      SignerMethod.nip44Encrypt,
      () async {
        final result = await js.nostr!.nip44!
            .encrypt(recipientPubkey.toJS, plaintext.toJS)
            .toDart;
        return result.toDart;
      },
      plaintext: plaintext,
      counterpartyPubkey: recipientPubkey,
    );
  }

  @override
  String getPublicKey() {
    if (cachedPublicKey != null) {
      return cachedPublicKey!;
    }

    js.nostr!.getPublicKey().toDart.then((pubkey) {
      cachedPublicKey = pubkey.toDart;
    });

    throw Exception('Use getPublicKeyAsync with Nip07Signer');
  }

  Future<String> getPublicKeyAsync() async {
    return _trackRequest(SignerMethod.getPublicKey, () async {
      final pubkey = (await js.nostr!.getPublicKey().toDart).toDart;
      cachedPublicKey = pubkey;
      return pubkey;
    });
  }

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    if (js.nostr == null) {
      throw Exception('NIP-07 extension not available');
    }

    return _trackRequest(SignerMethod.signEvent, () async {
      final jsEvent = js.NostrEvent()
        ..pubkey = event.pubkey
        ..createdAt = event.createdAt
        ..kind = event.kind
        ..content = event.content
        ..tags = event.tags
            .map((tag) => tag.map((item) => item.toJS).toList().toJS)
            .toList()
            .toJS;

      final signedEvent = await js.nostr!.signEvent(jsEvent).toDart;

      return event.copyWith(
        id: signedEvent.id!,
        sig: signedEvent.sig!,
        pubkey: signedEvent.pubkey,
        createdAt: signedEvent.createdAt,
        kind: signedEvent.kind,
        content: signedEvent.content,
        tags: signedEvent.tagsList,
      );
    }, event: event);
  }

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      _pendingRequestsController.stream;

  @override
  List<PendingSignerRequest> get pendingRequests =>
      _pendingRequests.values.map((entry) => entry.request).toList();

  @override
  bool cancelRequest(String requestId) {
    final entry = _pendingRequests.remove(requestId);
    if (entry == null) {
      return false;
    }

    entry.completer.completeError(SignerRequestCancelledException(requestId));
    _notifyPendingRequestsChange();
    return true;
  }

  @override
  Future<void> dispose() async {
    cancelAllQueued();
    await _pendingRequestsController.close();
  }
}
