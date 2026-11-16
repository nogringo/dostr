import 'package:dostr_nip01/dostr_nip01.dart';

/// What a [PendingSignerRequest] asks the signer to do.
enum SignerMethod {
  signEvent,
  nip04Encrypt,
  nip04Decrypt,
  nip44Encrypt,
  nip44Decrypt,
}

/// A request waiting for the user to approve it on an interactive signer
/// (NIP-46 bunker, NIP-07 extension, NIP-55 signer app).
sealed class PendingSignerRequest {
  /// what `cancelRequest` takes
  final String id;

  final DateTime createdAt;

  /// the pubkey of the signer the request waits on
  final String signerPubkey;

  PendingSignerRequest({
    required this.id,
    required this.createdAt,
    required this.signerPubkey,
  });

  SignerMethod get method;

  @override
  String toString() =>
      'PendingSignerRequest(id: $id, method: $method, createdAt: $createdAt)';
}

/// A signature waiting for the user.
class PendingSignRequest extends PendingSignerRequest {
  final Nip01Event event;

  PendingSignRequest({
    required super.id,
    required super.createdAt,
    required super.signerPubkey,
    required this.event,
  });

  @override
  SignerMethod get method => SignerMethod.signEvent;
}

/// A NIP-04 or NIP-44 encryption waiting for the user.
class PendingEncryptRequest extends PendingSignerRequest {
  @override
  final SignerMethod method;

  final String plaintext;
  final String recipientPubkey;

  PendingEncryptRequest.nip04({
    required super.id,
    required super.createdAt,
    required super.signerPubkey,
    required this.plaintext,
    required this.recipientPubkey,
  }) : method = SignerMethod.nip04Encrypt;

  PendingEncryptRequest.nip44({
    required super.id,
    required super.createdAt,
    required super.signerPubkey,
    required this.plaintext,
    required this.recipientPubkey,
  }) : method = SignerMethod.nip44Encrypt;
}

/// A NIP-04 or NIP-44 decryption waiting for the user.
class PendingDecryptRequest extends PendingSignerRequest {
  @override
  final SignerMethod method;

  final String ciphertext;
  final String senderPubkey;

  PendingDecryptRequest.nip04({
    required super.id,
    required super.createdAt,
    required super.signerPubkey,
    required this.ciphertext,
    required this.senderPubkey,
  }) : method = SignerMethod.nip04Decrypt;

  PendingDecryptRequest.nip44({
    required super.id,
    required super.createdAt,
    required super.signerPubkey,
    required this.ciphertext,
    required this.senderPubkey,
  }) : method = SignerMethod.nip44Decrypt;
}
