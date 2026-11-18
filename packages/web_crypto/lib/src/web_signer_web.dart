import 'dart:js_interop';
import 'dart:math';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip01/hex.dart';
import 'package:dostr_signer/dostr_signer.dart';

import 'js_interop.dart';

/// Makes [WebSigner]s.
class WebSignerFactory implements LocalSignerFactory {
  const WebSignerFactory();

  @override
  NostrSigner create(String privateKey) => WebSigner(privateKey);

  @override
  NostrSigner readOnly(String publicKey) => WebSigner.readOnly(publicKey);

  @override
  KeyPair generateKeyPair() {
    final random = Random.secure();
    while (true) {
      final privateKey = bytesToHex(
        List.generate(32, (_) => random.nextInt(256)),
      );
      try {
        return (privateKey: privateKey, publicKey: _publicKeyOf(privateKey));
      } on FormatException {
        // zero or not below the curve order: draw again, as Bip340 does
      }
    }
  }

  @override
  NostrSigner createWithNewKeyPair() {
    final (:privateKey, :publicKey) = generateKeyPair();
    return WebSigner._(privateKey, publicKey);
  }
}

String _publicKeyOf(String privateKey) {
  final crypto = nostrCrypto;
  try {
    return crypto.getPublicKey(privateKey.toJS).toDart;
  } catch (_) {
    throw const FormatException('Not a valid private key');
  }
}

/// A [NostrSigner] that holds its private key and signs, encrypts and
/// decrypts with @noble through JS interop: BIP-340, NIP-04 and NIP-44.
class WebSigner implements NostrSigner {
  /// The hex private key, or null for a read-only signer.
  final String? privateKey;

  @override
  final String publicKey;

  // Bounded: each gift wrap comes from a one-off key that never comes back.
  static const _maxConversationKeys = 256;
  final _conversationKeys = <String, JSUint8Array>{};

  /// A signer for [privateKey], with the public key it derives.
  ///
  /// Throws a [FormatException] when [privateKey] is not a valid private key.
  WebSigner(String privateKey) : this._(privateKey, _publicKeyOf(privateKey));

  /// A signer that knows [publicKey] only: [canSign] is false, and every
  /// other operation throws a [StateError].
  ///
  /// Throws a [FormatException] when [publicKey] is not 64 lowercase hex
  /// characters.
  WebSigner.readOnly(String publicKey)
    : this._(null, _checkedPublicKey(publicKey));

  WebSigner._(this.privateKey, this.publicKey);

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

    final id = event.payloadId;
    final sig = nostrCrypto.signEvent(key.toJS, id.toJS).toDart;
    return event.copyWith(id: id, sig: sig);
  }

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) async => _crypto(
    'NIP-04 decryption failed',
    (crypto, key) =>
        crypto.nip04Decrypt(key.toJS, senderPubkey.toJS, ciphertext.toJS),
  );

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) async => _crypto(
    'NIP-04 encryption failed',
    (crypto, key) =>
        crypto.nip04Encrypt(key.toJS, recipientPubkey.toJS, plaintext.toJS),
  );

  @override
  bool get canSign => privateKey != null;

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async => _crypto(
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
  }) async => _crypto(
    'NIP-44 decryption failed',
    (crypto, key) => crypto.nip44Decrypt(
      _conversationKey(crypto, key, senderPubkey),
      ciphertext.toJS,
    ),
  );

  String _privateKey() =>
      privateKey ??
      (throw StateError('A read-only signer cannot sign, encrypt or decrypt'));

  // the input comes from others, such as a ciphertext a relay served
  String _crypto(
    String failure,
    JSString Function(NostrCrypto crypto, String privateKey) run,
  ) {
    final key = _privateKey();
    final crypto = nostrCrypto;
    try {
      return run(crypto, key).toDart;
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
