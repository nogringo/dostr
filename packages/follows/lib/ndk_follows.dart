/// The contact lists of NDK (NIP-02): load one, and follow or unfollow as the
/// logged account.
///
/// ```dart
/// final follows = Follows(
///   query: query,
///   publish: publish,
///   cache: cache,
///   accounts: accounts,
/// );
/// final contactList = await follows.getContactList(pubkey);
/// await follows.broadcastAddContact(otherPubkey);
/// ```
library;

export 'src/contact_list.dart';
export 'src/contact_list_cache.dart';
export 'src/follows.dart';
