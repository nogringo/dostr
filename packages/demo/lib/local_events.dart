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
  ) async => [
    for (final event in _events.values)
      if (filter.matches(event)) (id: event.id, createdAt: event.createdAt),
  ];

  List<Nip01Event> eventsWithIds(Iterable<String> ids) => [
    for (final id in ids)
      if (_events[id] case final event?) event,
  ];
}
