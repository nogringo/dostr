import 'dart:async';

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:rxdart/rxdart.dart';

import 'nip65_fetcher.dart';
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

  /// When the relays last answered for each event, keyed by pubkey and kind:
  /// fetchers of one kind with different [dTag]s need a store each. A lookup
  /// a relay answered less than [maxAge] ago is answered from [cache] alone,
  /// unless the event it found is gone from it. Past [maxAge] the relays are
  /// asked again, and while none answers the last known state holds: the
  /// cached event, or [EventNotFound] when there was none.
  final UrlListCheckStore? checks;

  /// With [checks], how long a lookup a relay answered is trusted.
  final Duration maxAge;

  /// Only shows in logs.
  final String name;

  OutboxFetcher({
    required this._reqs,
    required this.kind,
    this.dTag,
    this.nip65Fetcher,
    this.relays = defaultIndexerRelays,
    this.timeout = const Duration(seconds: 5),
    this.cache,
    this.checks,
    this.maxAge = const Duration(minutes: 10),
    String? name,
  }) : name = name ?? 'kind-$kind';

  /// Each [kind] event of [pubKey] (hex) found on its write relays and on
  /// [relays], as soon as it arrives, if newer than the ones before it. The
  /// one in [cache] comes first, and [checks] may spare the relays.
  ///
  /// NIP-65 puts it on the write relays, asked as soon as a relay list
  /// arrives. [relays] are asked meanwhile, since many clients also publish
  /// there. Each relay is asked once.
  Stream<Nip01Event> watch(String pubKey) => _lookUp(pubKey).versions;

  /// The newest [kind] event of [pubKey] (hex) found on its write relays and
  /// on [relays], or null if none has one.
  Future<Nip01Event?> fetch(String pubKey) => lastVersion(watch(pubKey));

  /// How a lookup like [watch] ends for [pubKey].
  ///
  /// While no relay answers [nip65Fetcher], the write relays are unknown, and
  /// [relays] lacking the event does not make it [EventNotFound].
  Future<EventLookup> lookup(String pubKey) async {
    final lookup = _lookUp(pubKey);
    await lookup.versions.drain<void>();
    return lookup.result;
  }

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
        Stream<Nip01Event> askOn(List<String> urls) => askReplaceable(
          _reqs,
          kind: kind,
          pubKey: pubKey,
          dTag: dTag,
          relays: [
            for (final url in cleanRelayUrls(urls))
              if (asked.add(url)) url,
          ],
          name: name,
          timeout: timeout,
          outcomes: outcomes,
        );

        final nip65Fetcher = this.nip65Fetcher;
        // a lookup cancelled before its end never awaits it
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
