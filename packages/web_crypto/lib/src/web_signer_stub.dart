import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

/// Stub implementation for non-web platforms.
/// WebSignerFactory is only available on web platforms.
class WebSignerFactory implements LocalSignerFactory {
  const WebSignerFactory();

  Never _unsupported() => throw UnsupportedError(
    'WebSignerFactory is only available on web platforms. '
    'Use Bip340SignerFactory for native platforms.',
  );

  @override
  NostrSigner create(String privateKey) => _unsupported();

  @override
  NostrSigner readOnly(String publicKey) => _unsupported();

  @override
  (String, String) generateKeyPair() => _unsupported();

  @override
  NostrSigner createWithNewKeyPair() => _unsupported();
}

/// Stub implementation for non-web platforms.
/// WebSigner is only available on web platforms.
class WebSigner implements NostrSigner {
  /// hex private key
  String? privateKey;

  /// hex public key
  String publicKey;

  WebSigner({required this.privateKey, required this.publicKey}) {
    throw UnsupportedError(
      'WebSigner is only available on web platforms. '
      'Use Bip340Signer for native platforms.',
    );
  }

  @override
  Future<Nip01Event> sign(Nip01Event event) {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  String getPublicKey() {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  bool get canSign {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  List<PendingSignerRequest> get pendingRequests {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  bool cancelRequest(String requestId) {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }

  @override
  Future<void> dispose() async {
    throw UnsupportedError('WebSigner is only available on web platforms.');
  }
}
