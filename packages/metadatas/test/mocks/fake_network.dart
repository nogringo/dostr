import 'package:ndk_metadatas/ndk_metadatas.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

class MemoryMetadataCache implements MetadataCache {
  final List<Nip01Event> events = [];

  @override
  Future<Metadata?> loadMetadata(String pubKey) async {
    final found =
        events
            .where((e) => e.pubKey == pubKey && e.kind == Metadata.kKind)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return found.isEmpty ? null : Metadata.fromEvent(found.first);
  }

  @override
  Future<void> saveEvent(Nip01Event event) async => events.add(event);
}

typedef FakeQuery = ({
  Filter filter,
  Duration? timeout,
  bool cacheRead,
  Iterable<String>? relays,
});

/// Relays holding one metadata event per pubkey, the latest published.
class FakeRelays {
  final Map<String, Nip01Event> metadatas = {};
  final List<FakeQuery> queries = [];
  final List<({Nip01Event event, Iterable<String>? relays})> published = [];
  Object? queryError;

  Stream<Nip01Event> query(
    Filter filter, {
    Duration? timeout,
    required bool cacheRead,
    Iterable<String>? relays,
  }) async* {
    queries.add((
      filter: filter,
      timeout: timeout,
      cacheRead: cacheRead,
      relays: relays,
    ));
    if (queryError != null) throw queryError!;
    for (final author in filter.authors ?? const <String>[]) {
      final event = metadatas[author];
      if (event != null) yield event;
    }
  }

  Future<void> publish(Nip01Event event, {Iterable<String>? relays}) async {
    published.add((event: event, relays: relays));
    metadatas[event.pubKey] = event;
  }
}
