/// The NIP-51 lists and sets of NDK: load them, and add or remove public and
/// private elements as the logged account.
///
/// ```dart
/// final lists = Lists(
///   query: query,
///   publish: publish,
///   cache: cache,
///   accounts: accounts,
/// );
/// final mutes = await lists.getSingleNip51List(Nip51List.kMute);
/// await lists.addElementToList(
///   kind: Nip51List.kBookmarks,
///   tag: Nip51List.kThread,
///   value: eventId,
/// );
/// ```
library;

export 'src/lists.dart';
export 'src/nip_51_list.dart';
export 'src/nip_51_list_cache.dart';
export 'src/nip_51_list_plaintext_cache.dart';
export 'src/nip51_mute_event_filter.dart';
