import 'package:dostr_nip01/dostr_nip01.dart';
import 'pending_signer_request.dart';

/// A private key and its x-only public key, both 32 bytes in lowercase hex.
typedef KeyPair = ({String privateKey, String publicKey});

/// Makes the [NostrSigner]s that hold their key, with the crypto of one
/// platform.
abstract interface class LocalSignerFactory {
  /// A signer for [privateKey], whose public key it derives.
  NostrSigner create(String privateKey);

  /// A read-only signer for [publicKey], whose [NostrSigner.canSign] is false.
  ///
  /// Throws a [FormatException] when [publicKey] is not the 64 lowercase hex
  /// characters NIP-01 requires.
  NostrSigner readOnly(String publicKey);

  /// A new random key pair, for a caller that keeps the private key.
  KeyPair generateKeyPair();

  /// A signer for a new random key pair.
  NostrSigner createWithNewKeyPair();
}

/// Every operation completes with its result or throws a
/// [SignerRequestException]: a [SignerRequestRejectedException] when the
/// signer turns it down, a [SignerRequestCancelledException] after
/// [cancelRequest], a [SignerRequestFailedException] when no valid result came
/// back.
///
/// Misusing a signer throws an [Error] instead: an [ArgumentError] for [sign]
/// with an event of another pubkey, a [StateError] for any operation while
/// [canSign] is false. A signer used on a platform it does not run on throws
/// an [UnsupportedError].
abstract interface class NostrSigner {
  /// Signs [event], which must have the pubkey of [publicKey], or this
  /// throws an [ArgumentError].
  ///
  /// The signed event has that pubkey, and the id of its payload, whatever id
  /// [event] holds. An interactive signer may change other fields before it
  /// signs, such as `created_at`.
  Future<Nip01Event> sign(Nip01Event event);

  /// The hex pubkey this signer signs as. A signer knows it from the moment it
  /// exists, so this never throws.
  String get publicKey;

  /// false for a read-only account, or a signer that is not available here
  bool get canSign;

  /// Encrypts [plaintext] for [recipientPubkey] with NIP-04.
  @Deprecated('Use encryptNip44 instead. Deprecated by nostr spec. (nip04)')
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  });

  /// Decrypts a NIP-04 [ciphertext] that [senderPubkey] sent.
  @Deprecated('Use decryptNip44 instead. Deprecated by nostr spec. (nip04)')
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  });

  /// Encrypts [plaintext] for [recipientPubkey] with NIP-44.
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  });

  /// Decrypts a NIP-44 [ciphertext] that [senderPubkey] sent.
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  });

  /// Stream of pending requests waiting for user approval.
  /// Emits whenever the list changes (request added, completed, or cancelled).
  ///
  /// For local signers (like Bip340Signer), this will always emit an
  /// empty list. For interactive signers (NIP-46, NIP-07, NIP-55), this emits
  /// the signatures, encryptions and decryptions waiting for the user.
  Stream<List<PendingSignerRequest>> get pendingRequestsStream;

  /// Current list of pending requests (synchronous snapshot).
  ///
  /// Returns an empty list for local signers.
  List<PendingSignerRequest> get pendingRequests;

  /// Cancel a pending request by its ID.
  ///
  /// Returns true if the request was found and cancelled.
  /// The caller waiting on that request will receive a [SignerRequestCancelledException].
  ///
  /// This is a "soft cancel": the remote signer (bunker, browser extension,
  /// etc.) may still have the request pending. If the user approves it there
  /// after the cancellation, the result is ignored.
  bool cancelRequest(String requestId);

  /// Dispose of resources used by the signer.
  ///
  /// Call this when the signer is no longer needed to avoid memory leaks.
  Future<void> dispose();
}
