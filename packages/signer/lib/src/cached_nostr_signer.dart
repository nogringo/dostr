import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

import 'nostr_signer.dart';
import 'pending_signer_request.dart';

/// Where a [CachedNostrSigner] keeps what its signer decrypted with NIP-44.
///
/// Each plaintext comes with an opaque key, which the [CachedNostrSigner]
/// derives from the account pubkey, the sender pubkey and the ciphertext of
/// its decryption, and with that account pubkey, so that a store can keep
/// each account apart and [clear] one alone.
abstract interface class DecryptionCache {
  /// The plaintext stored under [key] for [accountPubkey], or null if there is
  /// none.
  Future<String?> load({required String accountPubkey, required String key});

  /// Stores [plaintext] under [key] for [accountPubkey].
  Future<void> save({
    required String accountPubkey,
    required String key,
    required String plaintext,
  });

  /// Removes every plaintext stored for [accountPubkey].
  Future<void> clear({required String accountPubkey});
}

/// A [DecryptionCache] that forgets everything on restart.
class MemoryDecryptionCache implements DecryptionCache {
  final Map<String, Map<String, String>> _plaintexts = {};

  @override
  Future<String?> load({
    required String accountPubkey,
    required String key,
  }) async => _plaintexts[accountPubkey]?[key];

  @override
  Future<void> save({
    required String accountPubkey,
    required String key,
    required String plaintext,
  }) async => (_plaintexts[accountPubkey] ??= {})[key] = plaintext;

  @override
  Future<void> clear({required String accountPubkey}) async =>
      _plaintexts.remove(accountPubkey);
}

/// A [NostrSigner] that keeps in [cache] what [signer] decrypts with NIP-44,
/// so that each ciphertext asks it once, and hands it everything else.
///
/// Concurrent decryptions of one ciphertext share one request. A decryption
/// reaches [signer], and its [pendingRequests], once [cache] answered. NIP-04
/// is not cached.
class CachedNostrSigner implements NostrSigner {
  final NostrSigner signer;
  final DecryptionCache cache;

  final Map<String, Future<String>> _decrypting = {};
  int _clears = 0;

  CachedNostrSigner(this.signer, {required this.cache});

  @override
  String get publicKey => signer.publicKey;

  @override
  bool get canSign => signer.canSign;

  @override
  Future<Nip01Event> sign(Nip01Event event) => signer.sign(event);

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) => signer.encryptNip04(
    plaintext: plaintext,
    recipientPubkey: recipientPubkey,
  );

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) => signer.decryptNip04(ciphertext: ciphertext, senderPubkey: senderPubkey);

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) => signer.encryptNip44(
    plaintext: plaintext,
    recipientPubkey: recipientPubkey,
  );

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) {
    final key = _keyOf(senderPubkey, ciphertext);
    return _decrypting[key] ??= _decrypt(key, ciphertext, senderPubkey)
        .whenComplete(() {
          _decrypting.remove(key);
        });
  }

  /// What [decryptNip44] gives from [cache] alone, without asking [signer],
  /// or null when [cache] does not hold it.
  Future<String?> decryptNip44FromCache({
    required String ciphertext,
    required String senderPubkey,
  }) => cache.load(
    accountPubkey: publicKey,
    key: _keyOf(senderPubkey, ciphertext),
  );

  // JSON keeps the three strings apart, whatever they hold
  String _keyOf(String senderPubkey, String ciphertext) => sha256
      .convert(utf8.encode(jsonEncode([publicKey, senderPubkey, ciphertext])))
      .toString();

  /// Removes from [cache] every plaintext of [publicKey], such as on logout.
  /// A decryption still running is not stored once it ends.
  Future<void> clearCache() {
    _clears++;
    return cache.clear(accountPubkey: publicKey);
  }

  Future<String> _decrypt(
    String key,
    String ciphertext,
    String senderPubkey,
  ) async {
    final clears = _clears;
    final cached = await cache.load(accountPubkey: publicKey, key: key);
    if (cached != null) return cached;
    final plaintext = await signer.decryptNip44(
      ciphertext: ciphertext,
      senderPubkey: senderPubkey,
    );
    if (clears == _clears) {
      await cache.save(
        accountPubkey: publicKey,
        key: key,
        plaintext: plaintext,
      );
    }
    return plaintext;
  }

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      signer.pendingRequestsStream;

  @override
  List<PendingSignerRequest> get pendingRequests => signer.pendingRequests;

  @override
  bool cancelRequest(String requestId) => signer.cancelRequest(requestId);

  /// Disposes of [signer], not of [cache].
  @override
  Future<void> dispose() => signer.dispose();
}
