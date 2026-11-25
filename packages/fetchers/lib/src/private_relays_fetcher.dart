import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';

import 'outbox_fetcher.dart';

/// Why [PrivateRelaysFetcher.relaysOf] could not decrypt a list.
class PrivateRelaysDecryptionException implements Exception {
  /// What kept the list from being decrypted.
  final String message;

  /// What the signer threw, if it did.
  final Object? cause;

  const PrivateRelaysDecryptionException(this.message, {this.cause});

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

/// Fetches users' NIP-37 private relay lists, `kind:10013`, from their write
/// relays, which [nip65Fetcher] finds, and from [relays], and decrypts them
/// with [relaysOf].
class PrivateRelaysFetcher extends OutboxFetcher {
  /// The signer of the account [pubkey], or null when it is not one here,
  /// such as `Accounts.getAccount` of `dostr_accounts`.
  final NostrSigner? Function(String pubkey) signerOf;

  PrivateRelaysFetcher({
    required super.reqs,
    required this.signerOf,
    super.nip65Fetcher,
    super.relays,
    super.timeout,
    super.cache,
    super.checks,
    super.maxAge,
    super.batchWindow,
  }) : super(kind: 10013, name: 'private-relays');

  /// The relays of [privateRelayList], a `kind:10013`, decrypted by the signer
  /// [signerOf] gives for its owner, with no timeout, then read by
  /// [privateRelaysOf]. A `CachedNostrSigner` of `dostr_signer` asks its
  /// signer once per version.
  ///
  /// Throws a [PrivateRelaysDecryptionException] when the owner has no signer
  /// here that can decrypt, or the signer fails.
  Future<List<RelayUrl>> relaysOf(Nip01Event privateRelayList) async {
    if (privateRelayList.content.isEmpty) return const [];
    final owner = privateRelayList.pubkey;
    final signer = signerOf(owner);
    if (signer == null || !signer.canSign) {
      throw PrivateRelaysDecryptionException(
        'no signer here decrypts the private relays of $owner',
      );
    }
    try {
      return privateRelaysOf(
        await signer.decryptNip44(
          ciphertext: privateRelayList.content,
          senderPubkey: owner,
        ),
      );
    } on SignerRequestException catch (e) {
      throw PrivateRelaysDecryptionException(
        'the private relays of $owner were not decrypted',
        cause: e,
      );
    }
  }
}

/// The normalized relays of [privateTags], the decrypted content of a
/// `kind:10013`: its `relay` tags, each once, in order. Content that is not a
/// JSON list of tags has none.
List<RelayUrl> privateRelaysOf(String privateTags) {
  final Object? tags;
  try {
    tags = jsonDecode(privateTags);
  } on FormatException {
    return const [];
  }
  if (tags is! List) return const [];
  return {
    for (final tag in tags)
      if (tag case ['relay', final String url, ...]) ?RelayUrl.tryParse(url),
  }.toList();
}
