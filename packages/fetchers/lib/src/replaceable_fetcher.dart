import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'lookup_checks.dart';
import 'replaceable_asks.dart';
import 'replaceable_events.dart';
import 'replaceable_lookup.dart';

/// Where [ReplaceableFetcher.locate] says the event of an account is, besides
/// the fetcher's relays: [relays], asked right away, then each list [found]
/// gives, asked as it comes. Once [found] ended, [unlocated] gives why the
/// relays that hold the event stayed unknown, or null when they were found.
typedef EventLocation = ({
  List<RelayUrl> relays,
  Stream<List<RelayUrl>> found,
  Future<String?> unlocated,
});

/// Fetches users' [kind] replaceable events, or addressable ones named
/// [dTag], from [relays] and from where [locate] says each one is.
///
/// Every fetcher reads one account three ways: [watch] gives each version as
/// it arrives, [fetch] the newest one, and [lookup] how the lookup ended.
abstract class ReplaceableFetcher {
  final RelayReqs _reqs;
  final int kind;
  final String? dTag;

  /// [defaultIndexerRelays] unless given.
  final List<RelayUrl> relays;
  final Duration timeout;

  /// Where the events found are kept. [watch] starts on the one it holds.
  final ReplaceableEventCache? cache;

  /// When the relays last answered for each event. A lookup a relay answered
  /// less than [maxAge] ago is answered from [cache] alone, unless the event
  /// it found is gone from it. Past [maxAge] the relays are asked again, and
  /// while none answers the last known state holds: the cached event, or
  /// [EventNotFound] when there was none.
  final LookupCheckStore? checks;

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

  ReplaceableFetcher({
    required RelayReqs reqs,
    required this.kind,
    this.dTag,
    List<RelayUrl>? relays,
    this.timeout = const Duration(seconds: 5),
    this.cache,
    this.checks,
    this.maxAge = const Duration(minutes: 10),
    this.batchWindow = defaultBatchWindow,
    required this.name,
  }) : _reqs = reqs,
       relays = relays ?? defaultIndexerRelays;

  /// Each [kind] event of [pubkey] (hex) found on [relays] and where [locate]
  /// says it is, as soon as it arrives, if newer than the ones before it. The
  /// one in [cache] comes first, and [checks] may spare the relays. Each relay
  /// is asked once.
  ///
  /// A lookup still running is reused, starting on the newest event it found
  /// so far, and so is one finished less than [maxAge] ago when there are no
  /// [checks]. Once started, a lookup runs until every relay answered or
  /// [timeout], even with no one listening.
  Stream<Nip01Event> watch(String pubkey) => _lookups.watch(pubkey);

  /// The newest [kind] event of [pubkey] (hex) that [watch] finds, or null if
  /// no relay has one.
  Future<Nip01Event?> fetch(String pubkey) => lastVersion(watch(pubkey));

  /// How the lookup [watch] runs for [pubkey] ended.
  ///
  /// While [locate] does not know where the event is, [relays] lacking it
  /// does not make it [EventNotFound].
  Future<EventLookup> lookup(String pubkey) => _lookups.lookup(pubkey);

  /// [fetch] for each of [pubkeys]. Their REQs go out once each lookup asked
  /// for them, without waiting for the end of [batchWindow].
  Future<Map<String, Nip01Event?>> fetchAll(Iterable<String> pubkeys) async =>
      foundEvents(await lookupAll(pubkeys));

  /// [lookup] for each of [pubkeys], their REQs sent as [fetchAll] does.
  Future<Map<String, EventLookup>> lookupAll(Iterable<String> pubkeys) =>
      _lookups.lookupAll(
        pubkeys,
        onAsked: (asking) {
          _asks.flush();
          locateAll(asking);
        },
      );

  /// Where the event of [pubkey] is, besides [relays]. Called once per lookup
  /// that asks the relays.
  @protected
  EventLocation locate(String pubkey);

  /// Called by [lookupAll] once the lookups of [pubkeys] asked the relays,
  /// to send now what [locate] still waits to send.
  @protected
  void locateAll(List<String> pubkeys) {}

  ReplaceableLookup _lookUp(String pubkey) {
    Future<String?>? unlocated;
    return lookUpReplaceable(
      kind: kind,
      pubkey: pubkey,
      dTag: dTag,
      cache: cache,
      checks: checks,
      maxAge: maxAge,
      ask: (outcomes) {
        final asked = <RelayUrl>{};
        Stream<Nip01Event> askOn(List<RelayUrl> urls) => _asks.ask(
          pubkey,
          relays: [
            for (final url in urls)
              if (asked.add(url)) url,
          ],
          outcomes: outcomes,
        );

        final location = locate(pubkey);
        // a lookup failing before its end never awaits it
        unlocated = location.unlocated..ignore();
        return MergeStream([
          askOn([...relays, ...location.relays]),
          location.found.flatMap(askOn),
        ]);
      },
      unlocated: () async => await unlocated,
    );
  }
}
