import 'package:ndk_metadatas/ndk_metadatas.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

import 'search_cache.dart';

/// The events relays hold for [filter], as they arrive. The stream ends once
/// the relays are done or the caller's timeout runs out.
typedef SearchQuery = Stream<Nip01Event> Function(Filter filter);

class Search {
  final SearchQuery _query;
  final SearchCache _cache;

  /// [cache] answers first, [query] adds what relays know.
  Search({required SearchQuery query, required SearchCache cache})
    : _query = query,
      _cache = cache;

  /// Search for metadata \
  /// [query] can be pubkey, name, nip05
  Future<List<Metadata>> metadataSearch(String query, {int limit = 10}) async {
    final result = await _cache.searchMetadatas(query, limit);
    return result.toList();
  }

  /// Search for events \
  /// [ids] list of event ids \
  /// [authors] list of authors \
  /// [kinds] list of kinds \
  /// [tags] map of tags \
  /// [since] timestamp since \
  /// [until] timestamp until \
  /// [search] search string \
  /// [limit] limit of results \
  /// [cacheOnly] if true only cache is used (a lot faster but no network fetch)
  Future<Iterable<Nip01Event>> searchEvents({
    List<String>? ids,
    List<String>? authors,
    List<int>? kinds,
    Map<String, List<String>>? tags,
    int? since,
    int? until,
    String? search,
    int limit = 100,

    /// cache only is much faster but does not fetch from the network
    bool cacheOnly = false,
  }) async {
    final localEvents = _cache.loadEvents(
      ids: ids,
      pubKeys: authors,
      kinds: kinds,
      tags: tags,
      since: since,
      until: until,
      search: search,
      limit: limit,
    );

    if (cacheOnly) {
      return localEvents;
    }

    final networkEvents = _query(
      Filter(
        authors: authors,
        kinds: kinds,
        tags: tags,
        since: since,
        until: until,
        search: search,
        limit: limit,
      ),
    ).toList();

    final events = await Future.wait([localEvents, networkEvents]);

    final combined = events.expand((element) => element);

    final withoutDuplicates = combined.toSet().toList();
    return withoutDuplicates;
  }
}
