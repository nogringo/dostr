import 'dart:async';
import 'dart:math';

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:rxdart/rxdart.dart';

import 'replaceable_events.dart';

/// Where the fetchers keep the events they found, so a cold start does not
/// ask the relays for each of them again. `CacheManagerReplaceableEvents` of
/// ndk implements it on a `CacheManager`.
abstract interface class ReplaceableEventCache {
  /// The stored [kind] event of [pubKey] (hex), named [dTag] if addressable,
  /// or null if there is none.
  Future<Nip01Event?> load({
    required int kind,
    required String pubKey,
    String? dTag,
  });

  /// Stores [event], newer than the one [load] gave.
  Future<void> save(Nip01Event event);
}

/// How the lookup of one replaceable event ended.
sealed class EventLookup {
  const EventLookup();
}

/// The newest version, from the cache or a relay.
final class EventFound extends EventLookup {
  final Nip01Event event;

  const EventFound(this.event);
}

/// A relay answered and none holds the event, or a check says it was absent.
final class EventNotFound extends EventLookup {
  const EventNotFound();
}

/// No relay answered, so whether the event exists is unknown.
final class EventUnavailable extends EventLookup {
  /// What each relay did, or why none was asked.
  final String reason;

  const EventUnavailable(this.reason);
}

/// [asked] completes once [versions] asked the relays, with true, or found it
/// needs not, with false. [result] completes once [versions] is done, and
/// never if it is cancelled.
typedef ReplaceableLookup = ({
  Stream<Nip01Event> versions,
  Future<bool> asked,
  Future<EventLookup> result,
});

/// The event each of [lookups] found, or null.
Map<String, Nip01Event?> foundEvents(Map<String, EventLookup> lookups) => {
  for (final MapEntry(key: pubKey, value: lookup) in lookups.entries)
    pubKey: switch (lookup) {
      EventFound(:final event) => event,
      _ => null,
    },
};

/// A lookup of the newest [kind] event of [pubKey], named [dTag] if
/// addressable: its versions start on the one in [cache], then each newer one
/// [ask] gets from the relays, filling the map it is given with what each
/// relay did.
///
/// Once [ask] ended, [unlocated] gives why the relays that hold the event
/// stayed unknown, or null when they were found. Then the other relays
/// lacking the event does not make it [EventNotFound].
///
/// With [checks], a lookup a relay answered less than [maxAge] ago is
/// answered from [cache] alone, unless the event it found is gone from it.
/// Past [maxAge] the relays are asked again, and while none answers the last
/// known state holds: the cached event, or [EventNotFound] when there was
/// none.
ReplaceableLookup lookUpReplaceable({
  required int kind,
  required String pubKey,
  String? dTag,
  required Stream<Nip01Event> Function(
    Map<String, RelayRequestOutcome> outcomes,
  )
  ask,
  Future<String?> Function()? unlocated,
  ReplaceableEventCache? cache,
  UrlListCheckStore? checks,
  required Duration maxAge,
}) {
  final asked = Completer<bool>();
  final result = Completer<EventLookup>();

  Stream<Nip01Event> versions() async* {
    final cached = await cache?.load(kind: kind, pubKey: pubKey, dTag: dTag);
    final check = await checks?.read(pubKey, kind, dTag: dTag);
    final now = DateTime.now().toUtc();
    if (cached != null) yield cached;
    if (_isFresh(check, cached != null, now, maxAge)) {
      asked.complete(false);
      result.complete(
        cached != null ? EventFound(cached) : const EventNotFound(),
      );
      return;
    }

    final outcomes = <String, RelayRequestOutcome>{};
    final answers = ask(outcomes);
    asked.complete(true);
    var newest = cached;
    yield* newerVersions(
      answers,
      kind: kind,
      pubKey: pubKey,
      dTag: dTag,
      after: cached,
    ).asyncMap((version) async {
      await cache?.save(version);
      return newest = version;
    });

    final unlocatedReason = await unlocated?.call();
    final answered =
        unlocatedReason == null &&
        outcomes.values.any(
          (outcome) => outcome.status == RelayRequestStatus.eose,
        );
    if (answered) {
      await checks?.write(
        UrlListCheck(
          pubkey: pubKey,
          kind: kind,
          dTag: dTag,
          checkedAt: now,
          found: newest != null,
        ),
      );
    }
    final found = newest;
    result.complete(switch (found) {
      final Nip01Event event => EventFound(event),
      null when answered || check?.found == false => const EventNotFound(),
      null => EventUnavailable(
        unlocatedReason ??
            (outcomes.isEmpty
                ? 'no relay asked'
                : [
                    for (final MapEntry(:key, :value) in outcomes.entries)
                      '$key: $value',
                  ].join(', ')),
      ),
    });
  }

  return (versions: versions(), asked: asked.future, result: result.future);
}

/// A check vouches for the cache while it is younger than [maxAge], unless
/// the event it found is no longer there. One from the future is a clock set
/// back since, and vouches for nothing.
bool _isFresh(UrlListCheck? check, bool cached, DateTime now, Duration maxAge) {
  if (check == null || check.checkedAt.isAfter(now)) return false;
  if (check.found && !cached) return false;
  return now.difference(check.checkedAt) < maxAge;
}

/// The lookups of one fetcher, one per pubkey: one still running is reused,
/// starting on the newest version it found so far, and so is one finished
/// less than [reuseFor] ago. Once started, a lookup runs to its end, even with
/// no one listening.
class SharedLookups {
  final ReplaceableLookup Function(String pubKey) _start;
  final Duration reuseFor;
  final Map<String, _SharedLookup> _lookups = {};
  int _sweepAt = _minSweep;

  static const _minSweep = 64;

  SharedLookups(this._start, {required this.reuseFor});

  /// How many lookups are kept, the stale ones until the next sweep.
  int get length => _lookups.length;

  Stream<Nip01Event> watch(String pubKey) => _lookupOf(pubKey).versions;

  Future<EventLookup> lookup(String pubKey) => _lookupOf(pubKey).done;

  /// The lookups of [pubKeys], each once. Once each of them asked the relays
  /// or found it needs not, [onAsked] gets the pubkeys that asked.
  Future<Map<String, EventLookup>> lookupAll(
    Iterable<String> pubKeys, {
    required void Function(List<String> asking) onAsked,
  }) async {
    final lookups = {for (final pubKey in pubKeys) pubKey: _lookupOf(pubKey)};
    final dones = [for (final lookup in lookups.values) lookup.done];
    final asked = await Future.wait([
      for (final (i, lookup) in lookups.values.indexed)
        Future.any([
          lookup.asked,
          // a lookup failing before it asked never completes asked
          dones[i].then((_) => false, onError: (_) => false),
        ]),
    ]);
    onAsked([
      for (final (i, pubKey) in lookups.keys.indexed)
        if (asked[i]) pubKey,
    ]);
    return Map.fromIterables(lookups.keys, await Future.wait(dones));
  }

  _SharedLookup _lookupOf(String pubKey) {
    final lookup = _lookups[pubKey];
    if (lookup != null && !lookup.isStale) return lookup;
    // swept on insertion: a timer would keep the isolate alive
    if (_lookups.length >= _sweepAt) {
      _lookups.removeWhere((_, lookup) => lookup.isStale);
      _sweepAt = max(_minSweep, 2 * _lookups.length);
    }
    return _lookups[pubKey] = _SharedLookup(_start(pubKey), reuseFor);
  }
}

class _SharedLookup {
  late final Stream<Nip01Event> versions;
  final Future<bool> asked;
  final Future<EventLookup> result;
  late final Future<EventLookup> done = versions.drain<void>().then(
    (_) => result,
  );
  DateTime? _staleAt;

  _SharedLookup(ReplaceableLookup lookup, Duration reuseFor)
    : asked = lookup.asked,
      result = lookup.result {
    versions = lookup.versions
        .doOnDone(() => _staleAt = DateTime.now().add(reuseFor))
        .publishReplay(maxSize: 1)
        .autoConnect();
  }

  bool get isStale {
    final staleAt = _staleAt;
    return staleAt != null && !DateTime.now().isBefore(staleAt);
  }
}
