import 'package:ndk_nip01/ndk_nip01.dart';

import 'metadata.dart';

/// Where [Search] looks before asking relays. NDK's `CacheManager`
/// implements it.
abstract interface class SearchCache {
  /// The cached metadata (kind 0) matching [search] by name, display name,
  /// NIP-05 or about, newest first, at most [limit].
  Future<Iterable<Metadata>> searchMetadatas(String search, int limit);

  /// Visible events only: of a replaceable or addressable event, just the
  /// version that supersedes the others. [search] matches the content.
  Future<List<Nip01Event>> loadEvents({
    List<String>? ids,
    List<String>? pubKeys,
    List<int>? kinds,
    Map<String, List<String>>? tags,
    int? since,
    int? until,
    String? search,
    int? limit,
  });
}
