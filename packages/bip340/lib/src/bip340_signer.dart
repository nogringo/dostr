import 'dart:typed_data';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip44/dostr_nip44.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import 'bip340.dart';

/// Default factory for creating Bip340Signer instances
class Bip340SignerFactory implements LocalSignerFactory {
  const Bip340SignerFactory();

  @override
  NostrSigner create(String privateKey) => Bip340Signer(
    privateKey: privateKey,
    publicKey: Bip340.getPublicKey(privateKey),
  );

  @override
  NostrSigner readOnly(String publicKey) =>
      Bip340Signer(privateKey: null, publicKey: publicKey);

  @override
  (String, String) generateKeyPair() {
    final keyPair = Bip340.generatePrivateKey();

    return (keyPair.privateKey!, keyPair.publicKey);
  }

  @override
  NostrSigner createWithNewKeyPair() {
    final (privateKey, publicKey) = generateKeyPair();
    return Bip340Signer(privateKey: privateKey, publicKey: publicKey);
  }
}

/// Pure Dart signer
class Bip340Signer implements NostrSigner {
  /// hex private key
  final String? privateKey;

  /// hex public key
  @override
  final String publicKey;

  // Bounded: each gift wrap comes from a one-off key that never comes back.
  static const _maxConversationKeys = 256;
  final _conversationKeys = <String, Uint8List>{};

  /// Get a new signer with the given keys
  Bip340Signer({required this.privateKey, required this.publicKey});

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
    return event.copyWith(sig: Bip340.sign(event.id, key));
  }

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) async => _crypto(
    'NIP-04 decryption failed',
    (key) => Nip04.decrypt(
      ciphertext,
      recipientPrivateKey: key,
      senderPublicKey: senderPubkey,
    ),
  );

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) async => _crypto(
    'NIP-04 encryption failed',
    (key) => Nip04.encrypt(
      plaintext,
      senderPrivateKey: key,
      recipientPublicKey: recipientPubkey,
    ),
  );

  @override
  bool get canSign {
    return privateKey?.trim().isNotEmpty ?? false;
  }

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async => _crypto(
    'NIP-44 encryption failed',
    (key) => Nip44.encrypt(plaintext, _conversationKey(key, recipientPubkey)),
  );

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async => _crypto(
    'NIP-44 decryption failed',
    (key) => Nip44.decrypt(ciphertext, _conversationKey(key, senderPubkey)),
  );

  String _privateKey() {
    final key = privateKey;
    if (key == null || key.trim().isEmpty) {
      throw StateError('A read-only signer cannot sign, encrypt or decrypt');
    }
    return key;
  }

  // the input comes from others, such as a ciphertext a relay served
  String _crypto(String failure, String Function(String privateKey) run) {
    final key = _privateKey();
    try {
      return run(key);
    } catch (error) {
      throw SignerRequestFailedException(failure, cause: error);
    }
  }

  Uint8List _conversationKey(String privateKey, String pubkey) {
    final key =
        _conversationKeys.remove(pubkey) ??
        Nip44.conversationKey(privateKey: privateKey, publicKey: pubkey);
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
