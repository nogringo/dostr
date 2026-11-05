import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:rxdart/rxdart.dart';

import 'home_relays.dart';
import 'replaceable_events.dart';
import 'replaceable_lookup.dart';

const int _kind = 10002;

/// Fetches NIP-65 relay lists from [relays], and from the user's home relays
/// when a [homeRelayList] is given.
///
/// The fetchers given the same [Nip65Fetcher] share its lookups.
class Nip65Fetcher {
  final RelayReqs _reqs;
  final List<String> relays;
  final HomeRelayList? homeRelayList;
  final Duration timeout;

  /// Where the lists found are kept. [watch] starts on the one it holds.
  final ReplaceableEventCache? cache;

  /// When the relays last answered for each list. A lookup a relay answered
  /// less than [maxAge] ago is answered from [cache] alone, unless the list it
  /// found is gone from it. Past [maxAge] the relays are asked again, and while
  /// none answers the last known state holds: the cached list, or
  /// [EventNotFound] when there was none.
  final UrlListCheckStore? checks;

  /// How long the result of a finished lookup is reused, the same as ndk's
  /// refresh of users' relay lists. With [checks], across restarts too.
  final Duration maxAge;

  final Map<String, _Lookup> _lookups = {};

  Nip65Fetcher({
    required this._reqs,
    this.relays = defaultIndexerRelays,
    this.homeRelayList,
    this.timeout = const Duration(seconds: 5),
    this.cache,
    this.checks,
    this.maxAge = const Duration(minutes: 10),
  });

  /// Each `kind:10002` event of [pubKey] (hex) found on [relays] and on its
  /// home relays, as soon as it arrives, if newer than the ones before it.
  /// The one in [cache] comes first, and [checks] may spare the relays.
  ///
  /// A lookup still running, or finished less than [maxAge] ago, is reused,
  /// starting on the newest list it found so far. Once started, a lookup runs
  /// until every relay answered or [timeout], even with no one listening.
  Stream<Nip01Event> watch(String pubKey) => _lookupOf(pubKey).versions;

  /// The newest `kind:10002` event of [pubKey] (hex) found on [relays] and on
  /// its home relays, or null if none has one.
  Future<Nip01Event?> fetch(String pubKey) => lastVersion(watch(pubKey));

  /// How the lookup [watch] runs for [pubKey] ended.
  Future<EventLookup> lookup(String pubKey) async {
    final lookup = _lookupOf(pubKey);
    await lookup.versions.drain<void>();
    return lookup.result;
  }

  _Lookup _lookupOf(String pubKey) {
    final lookup = _lookups[pubKey];
    if (lookup != null && !lookup.isStale) return lookup;
    return _lookups[pubKey] = _Lookup(_lookUp(pubKey), maxAge);
  }

  ReplaceableLookup _lookUp(String pubKey) => lookUpReplaceable(
    kind: _kind,
    pubKey: pubKey,
    cache: cache,
    checks: checks,
    maxAge: maxAge,
    ask: (outcomes) => askReplaceable(
      _reqs,
      kind: _kind,
      pubKey: pubKey,
      relays: [...relays, ...?homeRelayList?.homeRelaysOf(pubKey)],
      name: 'nip65',
      timeout: timeout,
      outcomes: outcomes,
    ),
  );
}

class _Lookup {
  late final Stream<Nip01Event> versions;
  final Future<EventLookup> result;
  DateTime? _staleAt;

  _Lookup(ReplaceableLookup lookup, Duration maxAge) : result = lookup.result {
    versions = lookup.versions
        .doOnDone(() => _staleAt = DateTime.now().add(maxAge))
        .publishReplay(maxSize: 1)
        .autoConnect();
  }

  bool get isStale {
    final staleAt = _staleAt;
    return staleAt != null && !DateTime.now().isBefore(staleAt);
  }
}

/// The normalized write relays of [relayList], a `kind:10002`: the `r` tags
/// not marked `read`, since NIP-65 makes an unmarked relay both.
List<String> writeRelaysOf(Nip01Event relayList) =>
    _relaysOf(relayList, except: 'read');

/// The normalized read relays of [relayList], a `kind:10002`: the `r` tags
/// not marked `write`.
List<String> readRelaysOf(Nip01Event relayList) =>
    _relaysOf(relayList, except: 'write');

/// Every normalized relay of [relayList], a `kind:10002`, whatever its marker.
List<String> allRelaysOf(Nip01Event relayList) => _relaysOf(relayList);

List<String> _relaysOf(Nip01Event relayList, {String? except}) =>
    cleanRelayUrls([
      for (final tag in relayList.tags)
        if (tag.length > 1 &&
            tag[0] == 'r' &&
            (except == null || tag.length < 3 || tag[2] != except))
          tag[1],
    ]).toSet().toList();
