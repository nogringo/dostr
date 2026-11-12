import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:rxdart/rxdart.dart';

import 'nip65_fetcher.dart';
import 'replaceable_asks.dart';
import 'replaceable_events.dart';
import 'replaceable_lookup.dart';

/// Fetches users' [kind] replaceable events, or addressable ones named
/// [dTag], from their write relays, which [nip65Fetcher] finds, and from
/// [relays].
class OutboxFetcher {
  final RelayReqs _reqs;
  final int kind;
  final String? dTag;
  final Nip65Fetcher? nip65Fetcher;
  final List<String> relays;
  final Duration timeout;

  /// Where the events found are kept. [watch] starts on the one it holds.
  final ReplaceableEventCache? cache;

  /// When the relays last answered for each event. A lookup a relay answered
  /// less than [maxAge] ago is answered from [cache] alone, unless the event
  /// it found is gone from it. Past [maxAge] the relays are asked again, and
  /// while none answers the last known state holds: the cached event, or
  /// [EventNotFound] when there was none.
  final UrlListCheckStore? checks;

  /// How long a finished lookup is trusted. Without [checks], its result is
  /// reused that long. With them, each lookup reads [cache] again, so an
  /// event saved there since is seen, and the checks spare the relays across
  /// restarts too.
  final Duration maxAge;

  /// Only shows in logs.
  final String name;

  /// How long the pubkeys looked up are gathered into one REQ per relay.
  final Duration batchWindow;

  late final SharedLookups _lookups = SharedLookups(
    _lookUp,
    reuseFor: checks == null ? maxAge : Duration.zero,
  );

  late final _asks = ReplaceableAsks(
    _reqs,
    kind: kind,
    dTag: dTag,
    name: name,
    timeout: timeout,
    window: batchWindow,
  );

  OutboxFetcher({
    required RelayReqs reqs,
    required this.kind,
    this.dTag,
    this.nip65Fetcher,
    this.relays = defaultIndexerRelays,
    this.timeout = const Duration(seconds: 5),
    this.cache,
    this.checks,
    this.maxAge = const Duration(minutes: 10),
    this.batchWindow = defaultBatchWindow,
    String? name,
  }) : _reqs = reqs,
       name = name ?? 'kind-$kind';

  /// Each [kind] event of [pubKey] (hex) found on its write relays and on
  /// [relays], as soon as it arrives, if newer than the ones before it. The
  /// one in [cache] comes first, and [checks] may spare the relays.
  ///
  /// NIP-65 puts it on the write relays, asked as soon as a relay list
  /// arrives. [relays] are asked meanwhile, since many clients also publish
  /// there. Each relay is asked once.
  ///
  /// A lookup still running is reused, starting on the newest event it found
  /// so far, and so is one finished less than [maxAge] ago when there are no
  /// [checks]. Once started, a lookup runs until every relay answered or
  /// [timeout], even with no one listening.
  Stream<Nip01Event> watch(String pubKey) => _lookups.watch(pubKey);

  /// The newest [kind] event of [pubKey] (hex) found on its write relays and
  /// on [relays], or null if none has one.
  Future<Nip01Event?> fetch(String pubKey) => lastVersion(watch(pubKey));

  /// How the lookup [watch] runs for [pubKey] ended.
  ///
  /// While no relay answers [nip65Fetcher], the write relays are unknown, and
  /// [relays] lacking the event does not make it [EventNotFound].
  Future<EventLookup> lookup(String pubKey) => _lookups.lookup(pubKey);

  /// [fetch] for each of [pubKeys]. Their REQs to [relays] and for their
  /// relay lists go out once each lookup asked for them, without waiting for
  /// the end of [batchWindow]. Their write relays are asked as for [fetch].
  Future<Map<String, Nip01Event?>> fetchAll(Iterable<String> pubKeys) async =>
      foundEvents(await lookupAll(pubKeys));

  /// [lookup] for each of [pubKeys], their REQs sent as [fetchAll] does.
  Future<Map<String, EventLookup>> lookupAll(Iterable<String> pubKeys) =>
      _lookups.lookupAll(
        pubKeys,
        onAsked: (asking) {
          _asks.flush();
          // their lookups started the relay list lookups this one reuses
          nip65Fetcher?.lookupAll(asking).ignore();
        },
      );

  ReplaceableLookup _lookUp(String pubKey) {
    Future<EventLookup>? nip65Lookup;
    return lookUpReplaceable(
      kind: kind,
      pubKey: pubKey,
      dTag: dTag,
      cache: cache,
      checks: checks,
      maxAge: maxAge,
      ask: (outcomes) {
        final asked = <String>{};
        Stream<Nip01Event> askOn(List<String> urls) => _asks.ask(
          pubKey,
          relays: [
            for (final url in cleanRelayUrls(urls))
              if (asked.add(url)) url,
          ],
          outcomes: outcomes,
        );

        final nip65Fetcher = this.nip65Fetcher;
        // a lookup failing before its end never awaits it
        nip65Lookup = nip65Fetcher?.lookup(pubKey)?..ignore();
        return MergeStream([
          askOn(relays),
          ?nip65Fetcher
              ?.watch(pubKey)
              .flatMap((relayList) => askOn(writeRelaysOf(relayList))),
        ]);
      },
      unlocated: () async => switch (await nip65Lookup) {
        EventUnavailable(:final reason) => 'relay list unavailable: $reason',
        _ => null,
      },
    );
  }
}
