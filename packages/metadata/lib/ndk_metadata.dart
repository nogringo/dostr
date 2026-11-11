/// The user metadata of NDK (NIP-01 kind 0): load the profiles of pubkeys,
/// publish the logged account's own, and search cached metadata and events
/// in the cache and on relays (NIP-50).
///
/// ```dart
/// final metadatas = Metadatas(
///   query: query,
///   publish: publish,
///   cache: cache,
///   accounts: accounts,
/// );
/// final metadata = await metadatas.loadMetadata(pubkey);
/// await metadatas.broadcastMetadata(Metadata(name: 'alice'));
///
/// final search = Search(query: searchQuery, cache: searchCache);
/// final profiles = await search.metadataSearch('alice');
/// final notes = await search.searchEvents(kinds: [1], search: 'lightning');
/// ```
library;

export 'src/metadata.dart';
export 'src/metadata_cache.dart';
export 'src/metadatas.dart';
export 'src/search.dart';
export 'src/search_cache.dart';
