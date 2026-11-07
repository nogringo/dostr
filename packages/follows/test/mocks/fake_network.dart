import 'package:ndk_follows/ndk_follows.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

class MemoryContactListCache implements ContactListCache {
  final List<Nip01Event> events = [];

  @override
  Future<ContactList?> loadContactList(String pubKey) async {
    final lists =
        events
            .where((e) => e.pubKey == pubKey && e.kind == ContactList.kKind)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return lists.isEmpty ? null : ContactList.fromEvent(lists.first);
  }

  @override
  Future<void> saveEvent(Nip01Event event) async => events.add(event);
}

/// Relays holding one contact list per pubkey, the latest published.
class FakeRelays {
  final Map<String, Nip01Event> contactLists = {};
  final List<({Nip01Event event, Iterable<String>? relays})> published = [];
  int queries = 0;
  Object? queryError;

  Future<List<Nip01Event>> query(
    Filter filter, {
    required Duration timeout,
  }) async {
    queries++;
    if (queryError != null) throw queryError!;
    return [
      for (final author in filter.authors ?? const <String>[])
        ?contactLists[author],
    ];
  }

  Future<void> publish(Nip01Event event, {Iterable<String>? relays}) async {
    published.add((event: event, relays: relays));
    contactLists[event.pubKey] = event;
  }
}
