import 'package:clock/clock.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

import 'event_rules.dart';
import 'event_store.dart';

/// An [EventStore] that lives as long as the process, without NIP-50 search.
///
/// It indexes the events by id, author, kind and single-letter tag, so a
/// filter reads only the events its most selective condition can match.
class MemoryEventStore implements EventStore {
  final Map<String, Nip01Event> _events = {};
  final Map<String, Set<String>> _idsByAuthor = {};
  final Map<int, Set<String>> _idsByKind = {};
  final Map<(String, String), Set<String>> _idsByTag = {};
  final Map<String, String> _versionAt = {};
  final Map<String, Set<String>> _deletionsOfId = {};
  final Map<String, Set<String>> _deletionsOfAddress = {};

  var _closed = false;

  @override
  Future<EventAddOutcome> add(Nip01Event event) async {
    _checkOpen();
    return _add(event, nowInSeconds(clock.now()));
  }

  @override
  Future<List<EventAddOutcome>> addAll(List<Nip01Event> events) async {
    _checkOpen();
    final now = nowInSeconds(clock.now());
    return [for (final event in events) _add(event, now)];
  }

  @override
  Future<List<Nip01Event>> query(List<Filter> filters) async {
    _checkOpen();
    return _query(filters, nowInSeconds(clock.now()));
  }

  @override
  Future<int> remove(List<Filter> filters) async {
    _checkOpen();
    final events = _query(filters, nowInSeconds(clock.now()));
    events.forEach(_drop);
    return events.length;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _events.clear();
    _idsByAuthor.clear();
    _idsByKind.clear();
    _idsByTag.clear();
    _versionAt.clear();
    _deletionsOfId.clear();
    _deletionsOfAddress.clear();
  }

  void _checkOpen() {
    if (_closed) throw StateError('the MemoryEventStore was closed');
  }

  EventAddOutcome _add(Nip01Event event, int now) {
    if (EventKindClassification.isEphemeralKind(event.kind)) {
      return EventAddOutcome.ephemeral;
    }
    if (isExpired(event, now)) return EventAddOutcome.expired;
    if (_events.containsKey(event.id)) return EventAddOutcome.duplicate;
    if (_isDeleted(event, now)) return EventAddOutcome.deleted;
    final address = addressOf(event);
    final current = _events[_versionAt[address]];
    if (current != null) {
      if (!isExpired(current, now) && !replaces(event, current)) {
        return EventAddOutcome.outdated;
      }
      _drop(current);
    }
    _insert(event, address);
    if (event.kind == deletionKind) _applyDeletion(event);
    return EventAddOutcome.stored;
  }

  bool _isDeleted(Nip01Event event, int now) {
    if (event.kind == deletionKind) return false;
    final address = addressOf(event);
    return _activeDeletions(
          _deletionsOfId[event.id],
          now,
        ).any((deletion) => canDelete(deletion, event)) ||
        _activeDeletions(
          _deletionsOfAddress[address],
          now,
        ).any((deletion) => event.createdAt <= deletion.createdAt);
  }

  Iterable<Nip01Event> _activeDeletions(Set<String>? ids, int now) => [
    for (final id in ids ?? const <String>{})
      if (_events[id] case final deletion? when !isExpired(deletion, now))
        deletion,
  ];

  void _applyDeletion(Nip01Event deletion) {
    for (final id in deletion.getTags('e')) {
      (_deletionsOfId[id] ??= {}).add(deletion.id);
      final target = _events[id];
      if (target != null && canDelete(deletion, target)) _drop(target);
    }
    for (final address in deletedAddresses(deletion)) {
      (_deletionsOfAddress[address] ??= {}).add(deletion.id);
      final target = _events[_versionAt[address]];
      if (target != null && target.createdAt <= deletion.createdAt) {
        _drop(target);
      }
    }
  }

  void _insert(Nip01Event event, String? address) {
    _events[event.id] = event;
    (_idsByAuthor[event.pubkey] ??= {}).add(event.id);
    (_idsByKind[event.kind] ??= {}).add(event.id);
    for (final tag in _indexedTags(event)) {
      (_idsByTag[tag] ??= {}).add(event.id);
    }
    if (address != null) _versionAt[address] = event.id;
  }

  void _drop(Nip01Event event) {
    if (_events.remove(event.id) == null) return;
    _removeFrom(_idsByAuthor, event.pubkey, event.id);
    _removeFrom(_idsByKind, event.kind, event.id);
    for (final tag in _indexedTags(event)) {
      _removeFrom(_idsByTag, tag, event.id);
    }
    final address = addressOf(event);
    if (address != null && _versionAt[address] == event.id) {
      _versionAt.remove(address);
    }
    if (event.kind == deletionKind) {
      for (final id in event.getTags('e')) {
        _removeFrom(_deletionsOfId, id, event.id);
      }
      for (final address in deletedAddresses(event)) {
        _removeFrom(_deletionsOfAddress, address, event.id);
      }
    }
  }

  static void _removeFrom<K>(Map<K, Set<String>> index, K key, String id) {
    final ids = index[key];
    if (ids == null) return;
    ids.remove(id);
    if (ids.isEmpty) index.remove(key);
  }

  List<Nip01Event> _query(List<Filter> filters, int now) {
    final found = <String, Nip01Event>{};
    for (final filter in filters) {
      for (final event in _matches(filter, now)) {
        found[event.id] = event;
      }
    }
    return found.values.toList()..sort(newestFirst);
  }

  List<Nip01Event> _matches(Filter filter, int now) {
    final limit = filter.limit;
    if (filter.search != null ||
        filter.matchesNothing ||
        (limit != null && limit <= 0)) {
      return const [];
    }
    final matches = <Nip01Event>[];
    final expired = <Nip01Event>[];
    for (final id in _candidates(filter)) {
      final event = _events[id]!;
      if (!filter.matches(event)) continue;
      (isExpired(event, now) ? expired : matches).add(event);
    }
    expired.forEach(_drop);
    matches.sort(newestFirst);
    return limit != null && matches.length > limit
        ? matches.sublist(0, limit)
        : matches;
  }

  Iterable<String> _candidates(Filter filter) {
    final conditions = <List<Set<String>>>[
      if (filter.ids case final ids?) [ids.where(_events.containsKey).toSet()],
      if (filter.authors case final authors?)
        [for (final author in authors) ?_idsByAuthor[author]],
      if (filter.kinds case final kinds?)
        [for (final kind in kinds) ?_idsByKind[kind]],
      if (filter.tags case final tags?)
        for (final MapEntry(key: name, value: values) in tags.entries)
          if (_isIndexedTag(name))
            [for (final value in values) ?_idsByTag[(name, value)]],
    ];
    if (conditions.isEmpty) return _events.keys;
    final smallest = conditions.reduce(
      (a, b) => _countOf(a) <= _countOf(b) ? a : b,
    );
    return {for (final ids in smallest) ...ids};
  }

  static int _countOf(List<Set<String>> buckets) =>
      buckets.fold(0, (count, ids) => count + ids.length);

  // NIP-01 has relays index the single-letter tags only.
  static bool _isIndexedTag(String name) => name.length == 1;

  static Iterable<(String, String)> _indexedTags(Nip01Event event) => [
    for (final tag in event.tags)
      if (tag case [final name, final value, ...] when _isIndexedTag(name))
        (name, value),
  ];
}
