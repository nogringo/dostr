import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

Never _unsupported() => throw UnsupportedError(
  'WebSigner and WebSignerFactory are only available on the web. '
  'Use Bip340Signer and Bip340SignerFactory on other platforms.',
);

/// Only on the web: on other platforms, every method throws an
/// [UnsupportedError].
class WebSignerFactory implements LocalSignerFactory {
  const WebSignerFactory();

  @override
  NostrSigner create(String privateKey) => _unsupported();

  @override
  NostrSigner readOnly(String publicKey) => _unsupported();

  @override
  KeyPair generateKeyPair() => _unsupported();

  @override
  NostrSigner createWithNewKeyPair() => _unsupported();
}

/// Only on the web: on other platforms, the constructors throw an
/// [UnsupportedError].
class WebSigner implements NostrSigner {
  WebSigner(String privateKey) {
    _unsupported();
  }

  WebSigner.readOnly(String publicKey) {
    _unsupported();
  }

  /// The hex private key, or null for a read-only signer.
  String? get privateKey => _unsupported();

  @override
  String get publicKey => _unsupported();

  @override
  bool get canSign => _unsupported();

  @override
  Future<Nip01Event> sign(Nip01Event event) => _unsupported();

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) => _unsupported();

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) => _unsupported();

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) => _unsupported();

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) => _unsupported();

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      _unsupported();

  @override
  List<PendingSignerRequest> get pendingRequests => _unsupported();

  @override
  bool cancelRequest(String requestId) => _unsupported();

  @override
  Future<void> dispose() => _unsupported();
}
