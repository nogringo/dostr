import 'package:dostr_nip01/dostr_nip01.dart';

/// Events kept in memory for the session, which NIP-77 compares with a
/// relay's.
class LocalEvents {
  final _events = <String, Nip01Event>{};

  void addAll(Iterable<Nip01Event> events) {
    for (final event in events) {
      _events[event.id] = event;
    }
  }

  Future<List<({String id, int createdAt})>> loadEventIds(
    Filter filter,
  ) async =>
      [
        for (final event in _events.values)
          if (_matches(filter, event))
            (id: event.id, createdAt: event.createdAt),
      ];

  Future<Nip01Event?> loadEvent(String id) async => _events[id];

  List<Nip01Event> eventsWithIds(Iterable<String> ids) => [
        for (final id in ids)
          if (_events[id] case final event?) event,
      ];
}

/// the fields of the filters this demo builds: ids, authors, kinds and time
bool _matches(Filter filter, Nip01Event event) =>
    (filter.ids?.contains(event.id) ?? true) &&
    (filter.authors?.contains(event.pubKey) ?? true) &&
    (filter.kinds?.contains(event.kind) ?? true) &&
    (filter.since == null || event.createdAt >= filter.since!) &&
    (filter.until == null || event.createdAt <= filter.until!);
