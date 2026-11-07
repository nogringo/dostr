/// The search of NDK: cached metadata, and events from the cache and from
/// relays (NIP-50).
///
/// ```dart
/// final search = Search(query: query, cache: cache);
/// final profiles = await search.metadataSearch('alice');
/// final notes = await search.searchEvents(kinds: [1], search: 'lightning');
/// ```
library;

export 'src/search.dart';
export 'src/search_cache.dart';
