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
  NostrSigner create({String? privateKey, String? publicKey}) {
    final derivedPublicKey =
        publicKey ?? (privateKey != null ? derivePublicKey(privateKey) : null);

    if (derivedPublicKey == null) {
      throw ArgumentError('Either publicKey or privateKey must be provided');
    }

    return Bip340Signer(privateKey: privateKey, publicKey: derivedPublicKey);
  }

  @override
  String derivePublicKey(String privateKey) {
    return Bip340.getPublicKey(privateKey);
  }

  @override
  (String, String) generateKeyPair() {
    final keyPair = Bip340.generatePrivateKey();

    return (keyPair.privateKey!, keyPair.publicKey);
  }

  @override
  NostrSigner createWithNewKeyPair() {
    final (privateKey, publicKey) = generateKeyPair();
    return create(privateKey: privateKey, publicKey: publicKey);
  }
}

/// Pure Dart signer
class Bip340Signer implements NostrSigner {
  /// hex private key
  final String? privateKey;

  /// hex public key
  String publicKey;

  // Bounded: each gift wrap comes from a one-off key that never comes back.
  static const _maxConversationKeys = 256;
  final _conversationKeys = <String, Uint8List>{};

  /// Get a new signer with the given keys
  Bip340Signer({required this.privateKey, required this.publicKey});

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    if (privateKey?.trim().isNotEmpty ?? false) {
      return event.copyWith(sig: Bip340.sign(event.id, privateKey!));
    }
    throw Exception('Private key is required for signing');
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
    return Nip04.decrypt(ciphertext, privateKey!, senderPubkey);
  }

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    return Nip04.encrypt(plaintext, privateKey!, recipientPubkey);
  }

  @override
  bool get canSign {
    return privateKey?.trim().isNotEmpty ?? false;
  }

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    return Nip44.encrypt(plaintext, _conversationKey(recipientPubkey));
  }

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    return Nip44.decrypt(ciphertext, _conversationKey(senderPubkey));
  }

  Uint8List _conversationKey(String pubkey) {
    final key =
        _conversationKeys.remove(pubkey) ??
        Nip44.conversationKey(privateKey!, pubkey);
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
