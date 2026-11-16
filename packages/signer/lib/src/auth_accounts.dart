import 'nostr_signer.dart';

/// The accounts relays (NIP-42) and Blossom servers may be authenticated as,
/// each one the [NostrSigner] of its pubkey.
abstract interface class AuthAccounts {
  /// null when nobody is logged in
  NostrSigner? getLoggedAccount();

  /// the account of [pubkey], null when [pubkey] is not one
  NostrSigner? getAccount(String pubkey);
}
