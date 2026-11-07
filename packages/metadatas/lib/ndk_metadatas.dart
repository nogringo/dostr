/// The user metadata of NDK (NIP-01 kind 0): load the profiles of pubkeys,
/// and publish the logged account's own.
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
/// ```
library;

export 'src/metadata.dart';
export 'src/metadata_cache.dart';
export 'src/metadatas.dart';
