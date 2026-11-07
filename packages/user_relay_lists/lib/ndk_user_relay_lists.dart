/// The relay lists of users for NDK: read them from NIP-65, or from the
/// content of a NIP-02 contact list, edit the one of the logged account, and
/// compute the relay set that covers a list of pubkeys.
///
/// ```dart
/// final userRelayLists = UserRelayLists(
///   query: query,
///   publish: publish,
///   cacheManager: cache,
///   accounts: accounts,
/// );
/// final relayList = await userRelayLists.getSingleUserRelayList(pubkey);
/// ```
library;

export 'src/relay_sets.dart';
export 'src/user_relay_lists.dart';
