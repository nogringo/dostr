import 'package:ndk_lists/ndk_lists.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

bool _matches(Filter filter, Nip01Event event) =>
    (filter.authors == null || filter.authors!.contains(event.pubKey)) &&
    (filter.kinds == null || filter.kinds!.contains(event.kind)) &&
    (filter.tags?['#d'] == null || filter.tags!['#d']!.contains(event.dTag));

class MemoryNip51ListCache implements Nip51ListCache {
  final List<Nip01Event> events = [];

  @override
  Future<List<Nip01Event>> loadEvents({
    List<String>? pubKeys,
    List<int>? kinds,
  }) async => events
      .where(
        (e) =>
            (pubKeys == null || pubKeys.contains(e.pubKey)) &&
            (kinds == null || kinds.contains(e.kind)),
      )
      .toList();

  @override
  Future<void> saveEvent(Nip01Event event) async {
    events.removeWhere((e) => e.id == event.id);
    events.add(event);
  }

  @override
  Future<void> removeEvent(String id) async =>
      events.removeWhere((e) => e.id == id);
}

class MemoryPlaintextCache implements Nip51ListPlaintextCache {
  final Map<String, String> plaintexts = {};
  int decryptions = 0;

  @override
  Future<String?> loadOrDecrypt({
    required Nip01Event event,
    required String viewerPubKey,
    required Future<String?> Function() decrypt,
  }) async {
    final key = '${event.id}|$viewerPubKey';
    final cached = plaintexts[key];
    if (cached != null) return cached;
    decryptions++;
    final plaintext = await decrypt();
    if (plaintext != null) plaintexts[key] = plaintext;
    return plaintext;
  }
}

typedef FakeQuery = ({Filter filter, Duration? timeout, bool cacheRead});

/// Relays keeping every event published to them.
class FakeRelays {
  final List<Nip01Event> events = [];
  final List<FakeQuery> queries = [];
  final List<({Nip01Event event, Iterable<String>? relays})> published = [];

  Stream<Nip01Event> query(
    Filter filter, {
    Duration? timeout,
    required bool cacheRead,
  }) async* {
    queries.add((filter: filter, timeout: timeout, cacheRead: cacheRead));
    for (final event in List.of(events)) {
      if (_matches(filter, event)) yield event;
    }
  }

  Future<void> publish(Nip01Event event, {Iterable<String>? relays}) async {
    published.add((event: event, relays: relays));
    events.add(event);
  }
}
