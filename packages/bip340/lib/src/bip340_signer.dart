import 'dart:typed_data';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip01/hex.dart';
import 'package:dostr_nip44/dostr_nip44.dart';
import 'package:dostr_signer/dostr_signer.dart';

import 'bip340.dart';

/// Default factory for creating Bip340Signer instances
class Bip340SignerFactory implements LocalSignerFactory {
  const Bip340SignerFactory();

  @override
  NostrSigner create(String privateKey) => Bip340Signer(privateKey);

  @override
  NostrSigner readOnly(String publicKey) => Bip340Signer.readOnly(publicKey);

  @override
  KeyPair generateKeyPair() => Bip340.generateKeyPair();

  @override
  NostrSigner createWithNewKeyPair() {
    final (:privateKey, :publicKey) = Bip340.generateKeyPair();
    return Bip340Signer._(privateKey, publicKey);
  }
}

/// Pure Dart signer
class Bip340Signer implements NostrSigner {
  /// The hex private key, or null for a read-only signer.
  final String? privateKey;

  @override
  final String publicKey;

  // Bounded: each gift wrap comes from a one-off key that never comes back.
  static const _maxConversationKeys = 256;
  final _conversationKeys = <String, Uint8List>{};

  /// A signer for [privateKey], with the public key it derives.
  ///
  /// Throws a [FormatException] when [privateKey] is not a valid private key.
  Bip340Signer(String privateKey)
    : this._(privateKey, Bip340.getPublicKey(privateKey));

  /// A signer that knows [publicKey] only: [canSign] is false, and every
  /// other operation throws a [StateError].
  ///
  /// Throws a [FormatException] when [publicKey] is not 64 lowercase hex
  /// characters.
  Bip340Signer.readOnly(String publicKey)
    : this._(null, _checkedPublicKey(publicKey));

  Bip340Signer._(this.privateKey, this.publicKey);

  static String _checkedPublicKey(String publicKey) =>
      isLowercaseHex(publicKey, length: 64)
      ? publicKey
      : throw const FormatException('Not a valid public key');

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
    return signPayload(event, key);
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
  bool get canSign => privateKey != null;

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

  String _privateKey() =>
      privateKey ??
      (throw StateError('A read-only signer cannot sign, encrypt or decrypt'));

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

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      Stream.value(const []);

  @override
  List<PendingSignerRequest> get pendingRequests => const [];

  @override
  bool cancelRequest(String requestId) => false;

  @override
  Future<void> dispose() async => _conversationKeys.clear();
}
