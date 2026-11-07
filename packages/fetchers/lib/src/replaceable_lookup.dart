import 'dart:async';

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_url_set/ndk_url_set.dart';

import 'replaceable_events.dart';

/// Where the fetchers keep the events they found, so a cold start does not
/// ask the relays for each of them again. `CacheManagerReplaceableEvents` of
/// ndk_cache implements it on a `CacheManager`.
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

/// [result] completes once [versions] is done, and never if it is cancelled.
typedef ReplaceableLookup = ({
  Stream<Nip01Event> versions,
  Future<EventLookup> result,
});

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
  final result = Completer<EventLookup>();

  Stream<Nip01Event> versions() async* {
    final cached = await cache?.load(kind: kind, pubKey: pubKey, dTag: dTag);
    final check = await checks?.read(pubKey, kind);
    final now = DateTime.now().toUtc();
    if (cached != null) yield cached;
    if (_isFresh(check, cached != null, now, maxAge)) {
      result.complete(
        cached != null ? EventFound(cached) : const EventNotFound(),
      );
      return;
    }

    final outcomes = <String, RelayRequestOutcome>{};
    var newest = cached;
    yield* newerVersions(
      ask(outcomes),
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

  return (versions: versions(), result: result.future);
}

/// A check vouches for the cache while it is younger than [maxAge], unless
/// the event it found is no longer there. One from the future is a clock set
/// back since, and vouches for nothing.
bool _isFresh(UrlListCheck? check, bool cached, DateTime now, Duration maxAge) {
  if (check == null || check.checkedAt.isAfter(now)) return false;
  if (check.found && !cached) return false;
  return now.difference(check.checkedAt) < maxAge;
}
