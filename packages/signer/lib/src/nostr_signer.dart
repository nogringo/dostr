import 'package:dostr_nip01/dostr_nip01.dart';
import 'pending_signer_request.dart';

/// Factory for creating [NostrSigner] instances.
///
/// If [LocalSignerFactory.create] is called without a `publicKey`,
/// implementations must derive it from the `privateKey`.
abstract interface class LocalSignerFactory {
  /// Creates a NostrSigner instance.
  ///
  /// If [publicKey] is null, implementations MUST derive it from [privateKey].
  /// At least one of [privateKey] or [publicKey] must be provided!
  NostrSigner create({String? privateKey, String? publicKey});

  /// Derives a public key from a private key.
  /// Implementations MUST provide the derivation logic.
  String derivePublicKey(String privateKey);

  /// Generates a new keypair.
  /// Returns a record with (privateKey, publicKey).
  (String privateKey, String publicKey) generateKeyPair();

  /// Generates a new NostrSigner with a fresh keypair.
  NostrSigner createWithNewKeyPair();
}

/// Every operation completes with its result or throws: a
/// [SignerRequestRejectedException] when the user says no on the signer, a
/// [SignerRequestCancelledException] after [cancelRequest].
abstract interface class NostrSigner {
  /// Signs the given event and returns the signed event
  Future<Nip01Event> sign(Nip01Event event);

  String getPublicKey();

  /// false for a read-only account
  bool get canSign;

  @Deprecated('Use encryptNip44 instead. Deprecated by nostr spec. (nip04)')
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  });

  @Deprecated('Use decryptNip44 instead. Deprecated by nostr spec. (nip04)')
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  });

  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  });

  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  });

  /// Stream of pending requests waiting for user approval.
  /// Emits whenever the list changes (request added, completed, or cancelled).
  ///
  /// For local signers (like Bip340Signer), this will always emit an
  /// empty list. For interactive signers (NIP-46, NIP-07, NIP-55), this emits
  /// requests currently waiting for user approval or external completion.
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
  /// Note: This is a "soft cancel" - the remote signer (bunker, browser extension, etc.)
  /// may still have the request pending. If the user approves on the remote side
  /// after cancellation, the result will be ignored.
  bool cancelRequest(String requestId);

  /// Dispose of resources used by the signer.
  ///
  /// Call this when the signer is no longer needed to avoid memory leaks.
  Future<void> dispose();
}
