import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_home_relays/dostr_home_relays.dart';
import 'package:dostr_url_set/dostr_url_set.dart';

import 'replaceable_asks.dart';
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

  /// How long a finished lookup is trusted, the same as ndk's refresh of
  /// users' relay lists. Without [checks], its result is reused that long.
  /// With them, each lookup reads [cache] again, so a list saved there since
  /// is seen, and the checks spare the relays across restarts too.
  final Duration maxAge;

  /// How long the pubkeys looked up are gathered into one REQ per relay.
  final Duration batchWindow;

  late final SharedLookups _lookups = SharedLookups(
    _lookUp,
    reuseFor: checks == null ? maxAge : Duration.zero,
  );

  late final _asks = ReplaceableAsks(
    _reqs,
    kind: _kind,
    name: 'nip65',
    timeout: timeout,
    window: batchWindow,
  );

  Nip65Fetcher({
    required RelayReqs reqs,
    this.relays = defaultIndexerRelays,
    this.homeRelayList,
    this.timeout = const Duration(seconds: 5),
    this.cache,
    this.checks,
    this.maxAge = const Duration(minutes: 10),
    this.batchWindow = defaultBatchWindow,
  }) : _reqs = reqs;

  /// Each `kind:10002` event of [pubKey] (hex) found on [relays] and on its
  /// home relays, as soon as it arrives, if newer than the ones before it.
  /// The one in [cache] comes first, and [checks] may spare the relays.
  ///
  /// A lookup still running is reused, starting on the newest list it found
  /// so far, and so is one finished less than [maxAge] ago when there are no
  /// [checks]. Once started, a lookup runs until every relay answered or
  /// [timeout], even with no one listening.
  Stream<Nip01Event> watch(String pubKey) => _lookups.watch(pubKey);

  /// The newest `kind:10002` event of [pubKey] (hex) found on [relays] and on
  /// its home relays, or null if none has one.
  Future<Nip01Event?> fetch(String pubKey) => lastVersion(watch(pubKey));

  /// How the lookup [watch] runs for [pubKey] ended.
  Future<EventLookup> lookup(String pubKey) => _lookups.lookup(pubKey);

  /// [fetch] for each of [pubKeys]. Their REQs go out once each lookup asked
  /// for them, without waiting for the end of [batchWindow].
  Future<Map<String, Nip01Event?>> fetchAll(Iterable<String> pubKeys) async =>
      foundEvents(await lookupAll(pubKeys));

  /// [lookup] for each of [pubKeys], their REQs sent as [fetchAll] does.
  Future<Map<String, EventLookup>> lookupAll(Iterable<String> pubKeys) =>
      _lookups.lookupAll(pubKeys, onAsked: (_) => _asks.flush());

  ReplaceableLookup _lookUp(String pubKey) => lookUpReplaceable(
    kind: _kind,
    pubKey: pubKey,
    cache: cache,
    checks: checks,
    maxAge: maxAge,
    ask: (outcomes) => _asks.ask(
      pubKey,
      relays: [...relays, ...?homeRelayList?.homeRelaysOf(pubKey)],
      outcomes: outcomes,
    ),
  );
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
