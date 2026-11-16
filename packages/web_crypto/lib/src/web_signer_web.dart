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
  NostrSigner create({String? privateKey, String? publicKey}) {
    final derivedPublicKey =
        publicKey ?? (privateKey != null ? derivePublicKey(privateKey) : null);

    if (derivedPublicKey == null) {
      throw ArgumentError('Either publicKey or privateKey must be provided');
    }

    return WebSigner(privateKey: privateKey, publicKey: derivedPublicKey);
  }

  @override
  String derivePublicKey(String privateKey) {
    WebSigner._injectJS();
    return WebSigner._requireNostrCrypto().getPublicKey(privateKey.toJS).toDart;
  }

  @override
  (String, String) generateKeyPair() {
    final random = Random.secure();
    final privateKey = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return (privateKey, derivePublicKey(privateKey));
  }

  @override
  NostrSigner createWithNewKeyPair() {
    final (privateKey, publicKey) = generateKeyPair();
    return create(privateKey: privateKey, publicKey: publicKey);
  }
}

/// Web implementation of NostrSigner using @noble/curves and Web Crypto API
/// via JS interop for fast BIP-340 signing, NIP-04 and NIP-44 encryption.
class WebSigner implements NostrSigner {
  /// hex private key
  final String? privateKey;

  /// hex public key
  String publicKey;

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
    if (privateKey == null || privateKey!.isEmpty) {
      throw Exception('Private key is required for signing');
    }

    final crypto = await _getCrypto();
    final signature = await crypto
        .signEvent(privateKey!.toJS, event.id.toJS)
        .toDart;

    return event.copyWith(sig: signature.toDart);
  }

  @override
  String getPublicKey() {
    return publicKey;
  }

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    if (privateKey == null || privateKey!.isEmpty) {
      throw Exception('Private key is required for decryption');
    }
    final crypto = await _getCrypto();
    final result = await crypto
        .nip04Decrypt(privateKey!.toJS, senderPubkey.toJS, ciphertext.toJS)
        .toDart;
    return result.toDart;
  }

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    if (privateKey == null || privateKey!.isEmpty) {
      throw Exception('Private key is required for encryption');
    }
    final crypto = await _getCrypto();
    final result = await crypto
        .nip04Encrypt(privateKey!.toJS, recipientPubkey.toJS, plaintext.toJS)
        .toDart;
    return result.toDart;
  }

  @override
  bool get canSign {
    return privateKey != null && privateKey!.isNotEmpty;
  }

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    if (privateKey == null || privateKey!.isEmpty) {
      throw Exception('Private key is required for encryption');
    }
    final crypto = await _getCrypto();
    final result = await crypto
        .nip44Encrypt(_conversationKey(crypto, recipientPubkey), plaintext.toJS)
        .toDart;
    return result.toDart;
  }

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    if (privateKey == null || privateKey!.isEmpty) {
      throw Exception('Private key is required for decryption');
    }
    final crypto = await _getCrypto();
    final result = await crypto
        .nip44Decrypt(_conversationKey(crypto, senderPubkey), ciphertext.toJS)
        .toDart;
    return result.toDart;
  }

  JSUint8Array _conversationKey(NostrCrypto crypto, String pubkey) {
    final key =
        _conversationKeys.remove(pubkey) ??
        crypto.nip44ConversationKey(privateKey!.toJS, pubkey.toJS);
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
