import 'package:ndk_metadatas/ndk_metadatas.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_search/ndk_search.dart';

typedef LoadEventsCall = ({
  List<String>? ids,
  List<String>? pubKeys,
  List<int>? kinds,
  Map<String, List<String>>? tags,
  int? since,
  int? until,
  String? search,
  int? limit,
});

class MemorySearchCache implements SearchCache {
  final List<Nip01Event> events = [];
  final List<LoadEventsCall> loads = [];
  final List<({String search, int limit})> metadataSearches = [];

  @override
  Future<Iterable<Metadata>> searchMetadatas(String search, int limit) async {
    metadataSearches.add((search: search, limit: limit));
    return events
        .where((e) => e.kind == Metadata.kKind)
        .map(Metadata.fromEvent)
        .where((m) => m.matchesSearch(search))
        .take(limit);
  }

  @override
  Future<List<Nip01Event>> loadEvents({
    List<String>? ids,
    List<String>? pubKeys,
    List<int>? kinds,
    Map<String, List<String>>? tags,
    int? since,
    int? until,
    String? search,
    int? limit,
  }) async {
    loads.add((
      ids: ids,
      pubKeys: pubKeys,
      kinds: kinds,
      tags: tags,
      since: since,
      until: until,
      search: search,
      limit: limit,
    ));
    return [
      for (final e in events)
        if ((kinds == null || kinds.contains(e.kind)) &&
            (search == null || e.content.contains(search)))
          e,
    ];
  }
}

/// Relays answering every query with all the events they hold.
class FakeRelays {
  final List<Nip01Event> events = [];
  final List<Filter> queries = [];

  Stream<Nip01Event> query(Filter filter) async* {
    queries.add(filter);
    for (final event in events) {
      yield event;
    }
  }
}
