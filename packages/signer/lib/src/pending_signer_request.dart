import 'package:dostr_nip01/dostr_nip01.dart';

/// The encryption of a [PendingEncryptRequest] or a [PendingDecryptRequest].
enum EncryptionScheme { nip04, nip44 }

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

  @override
  String toString() => switch (this) {
    PendingSignRequest(:final event) =>
      'PendingSignRequest(id: $id, kind: ${event.kind}, createdAt: $createdAt)',
    PendingEncryptRequest(:final scheme) =>
      'PendingEncryptRequest(id: $id, ${scheme.name}, createdAt: $createdAt)',
    PendingDecryptRequest(:final scheme) =>
      'PendingDecryptRequest(id: $id, ${scheme.name}, createdAt: $createdAt)',
  };
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
}

/// A NIP-04 or NIP-44 encryption waiting for the user.
class PendingEncryptRequest extends PendingSignerRequest {
  final EncryptionScheme scheme;

  final String plaintext;
  final String recipientPubkey;

  PendingEncryptRequest.nip04({
    required super.id,
    required super.createdAt,
    required super.signerPubkey,
    required this.plaintext,
    required this.recipientPubkey,
  }) : scheme = EncryptionScheme.nip04;

  PendingEncryptRequest.nip44({
    required super.id,
    required super.createdAt,
    required super.signerPubkey,
    required this.plaintext,
    required this.recipientPubkey,
  }) : scheme = EncryptionScheme.nip44;
}

/// A NIP-04 or NIP-44 decryption waiting for the user.
class PendingDecryptRequest extends PendingSignerRequest {
  final EncryptionScheme scheme;

  final String ciphertext;
  final String senderPubkey;

  PendingDecryptRequest.nip04({
    required super.id,
    required super.createdAt,
    required super.signerPubkey,
    required this.ciphertext,
    required this.senderPubkey,
  }) : scheme = EncryptionScheme.nip04;

  PendingDecryptRequest.nip44({
    required super.id,
    required super.createdAt,
    required super.signerPubkey,
    required this.ciphertext,
    required this.senderPubkey,
  }) : scheme = EncryptionScheme.nip44;
}
