import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web/web.dart' as web;

import 'js_interop.dart';
import 'nostr_crypto_js.dart';

/// Web factory: produces [WebSigner] instances using @noble/curves.
class WebSignerFactory implements LocalSignerFactory {
  const WebSignerFactory();

  @override
  NostrSigner create(String privateKey) =>
      WebSigner(privateKey: privateKey, publicKey: _publicKeyOf(privateKey));

  @override
  NostrSigner readOnly(String publicKey) =>
      WebSigner(privateKey: null, publicKey: publicKey);

  @override
  (String, String) generateKeyPair() {
    final random = Random.secure();
    final privateKey = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return (privateKey, _publicKeyOf(privateKey));
  }

  @override
  NostrSigner createWithNewKeyPair() {
    final (privateKey, publicKey) = generateKeyPair();
    return WebSigner(privateKey: privateKey, publicKey: publicKey);
  }

  String _publicKeyOf(String privateKey) {
    WebSigner._injectJS();
    return WebSigner._requireNostrCrypto().getPublicKey(privateKey.toJS).toDart;
  }
}

/// Web implementation of NostrSigner using @noble/curves and Web Crypto API
/// via JS interop for fast BIP-340 signing, NIP-04 and NIP-44 encryption.
class WebSigner implements NostrSigner {
  /// hex private key
  final String? privateKey;

  /// hex public key
  @override
  final String publicKey;

  final Completer<bool> _isInitialized = Completer<bool>();
  static bool _jsInjected = false;

  // Bounded: each gift wrap comes from a one-off key that never comes back.
  static const _maxConversationKeys = 256;
  final _conversationKeys = <String, JSUint8Array>{};

  /// Get a new web signer with the given keys
  WebSigner({required this.privateKey, required this.publicKey}) {
    _init();
  }

  Future<void> _init() async {
    if (!_jsInjected) {
      _injectJS();
      _jsInjected = true;
    }
    _isInitialized.complete(true);
  }

  static void _injectJS() {
    // Check if already loaded (e.g., via index.html or WebEventVerifier)
    if (nostrCrypto != null) {
      return;
    }

    final script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.type = 'text/javascript';
    script.text = nostrCryptoJs;
    web.document.head?.appendChild(script);
  }

  static NostrCrypto _requireNostrCrypto() =>
      nostrCrypto ??
      (throw Exception(
        'NostrCrypto not available. JS injection may have failed.',
      ));

  Future<NostrCrypto> _getCrypto() async {
    await _isInitialized.future;
    return _requireNostrCrypto();
  }

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    final key = _privateKey();
    if (event.pubkey != publicKey) {
      throw ArgumentError.value(
        event.pubkey,
        'event.pubkey',
        'is not the pubkey of the signer, $publicKey',
      );
    }

    final id = event.payloadId;
    final crypto = await _getCrypto();
    final signature = await crypto.signEvent(key.toJS, id.toJS).toDart;

    return event.copyWith(id: id, sig: signature.toDart);
  }

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) => _crypto(
    'NIP-04 decryption failed',
    (crypto, key) =>
        crypto.nip04Decrypt(key.toJS, senderPubkey.toJS, ciphertext.toJS),
  );

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) => _crypto(
    'NIP-04 encryption failed',
    (crypto, key) =>
        crypto.nip04Encrypt(key.toJS, recipientPubkey.toJS, plaintext.toJS),
  );

  @override
  bool get canSign {
    return privateKey != null && privateKey!.isNotEmpty;
  }

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) => _crypto(
    'NIP-44 encryption failed',
    (crypto, key) => crypto.nip44Encrypt(
      _conversationKey(crypto, key, recipientPubkey),
      plaintext.toJS,
    ),
  );

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) => _crypto(
    'NIP-44 decryption failed',
    (crypto, key) => crypto.nip44Decrypt(
      _conversationKey(crypto, key, senderPubkey),
      ciphertext.toJS,
    ),
  );

  String _privateKey() {
    final key = privateKey;
    if (key == null || key.isEmpty) {
      throw StateError('A read-only signer cannot sign, encrypt or decrypt');
    }
    return key;
  }

  // the input comes from others, such as a ciphertext a relay served
  Future<String> _crypto(
    String failure,
    JSPromise<JSString> Function(NostrCrypto crypto, String privateKey) run,
  ) async {
    final key = _privateKey();
    final crypto = await _getCrypto();
    try {
      return (await run(crypto, key).toDart).toDart;
    } catch (error) {
      throw SignerRequestFailedException(failure, cause: error);
    }
  }

  JSUint8Array _conversationKey(
    NostrCrypto crypto,
    String privateKey,
    String pubkey,
  ) {
    final key =
        _conversationKeys.remove(pubkey) ??
        crypto.nip44ConversationKey(privateKey.toJS, pubkey.toJS);
    if (_conversationKeys.length >= _maxConversationKeys) {
      _conversationKeys.remove(_conversationKeys.keys.first);
    }
    return _conversationKeys[pubkey] = key;
  }

  // Local signer - no pending requests (operations are instant)
  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      _pendingRequestsController.stream;

  @override
  List<PendingSignerRequest> get pendingRequests => [];

  @override
  bool cancelRequest(String requestId) => false;

  @override
  Future<void> dispose() async {
    _conversationKeys.clear();
    await _pendingRequestsController.close();
  }
}
