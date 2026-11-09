import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:rxdart/rxdart.dart';

import 'blossom_servers_fetcher.dart';
import 'dm_relays_fetcher.dart';
import 'nip65_fetcher.dart';
import 'replaceable_lookup.dart';

/// A [UrlListFn] that reads the lists with these fetchers, their cache and
/// checks included.
///
/// The `outboxRelays` it is given go unused: [dmRelays] and [blossomServers]
/// find the write relays with [nip65], which must be their `nip65Fetcher`.
/// Private relay lists (kind 10013) are not supported.
UrlListFn fetcherUrlListFn({
  required Nip65Fetcher nip65,
  required DmRelaysFetcher dmRelays,
  required BlossomServersFetcher blossomServers,
}) {
  _requireNip65(nip65, dmRelays, blossomServers);
  return (pubkey, kind, _) async => switch (kind) {
    UrlListKind.outbox => _urls(await nip65.lookup(pubkey), writeRelaysOf),
    UrlListKind.inbox => _urls(await nip65.lookup(pubkey), readRelaysOf),
    UrlListKind.nip65 => _urls(await nip65.lookup(pubkey), allRelaysOf),
    UrlListKind.dm => _urls(await dmRelays.lookup(pubkey), dmRelaysOf),
    UrlListKind.blossom => _urls(
      await blossomServers.lookup(pubkey),
      blossomServersOf,
    ),
    UrlListKind.private => throw UnsupportedError(
      'private relay lists are not supported',
    ),
  };
}

/// A [UrlListWatchFn] for [watchUrlSet] that watches the lists with these
/// fetchers, their cache and checks included: each version they find comes
/// as found, the cached one first.
///
/// The `outboxRelays` it is given go unused, as for [fetcherUrlListFn]:
/// [dmRelays] and [blossomServers] ask the write relays as soon as [nip65]
/// finds them. Private relay lists (kind 10013) are not supported.
UrlListWatchFn fetcherUrlListWatchFn({
  required Nip65Fetcher nip65,
  required DmRelaysFetcher dmRelays,
  required BlossomServersFetcher blossomServers,
}) {
  _requireNip65(nip65, dmRelays, blossomServers);
  return (pubkey, kind, _) => switch (kind) {
    UrlListKind.outbox => _watchUrls(
      pubkey,
      nip65.watch,
      nip65.lookup,
      writeRelaysOf,
    ),
    UrlListKind.inbox => _watchUrls(
      pubkey,
      nip65.watch,
      nip65.lookup,
      readRelaysOf,
    ),
    UrlListKind.nip65 => _watchUrls(
      pubkey,
      nip65.watch,
      nip65.lookup,
      allRelaysOf,
    ),
    UrlListKind.dm => _watchUrls(
      pubkey,
      dmRelays.watch,
      dmRelays.lookup,
      dmRelaysOf,
    ),
    UrlListKind.blossom => _watchUrls(
      pubkey,
      blossomServers.watch,
      blossomServers.lookup,
      blossomServersOf,
    ),
    UrlListKind.private => Stream.error(
      UnsupportedError('private relay lists are not supported'),
    ),
  };
}

void _requireNip65(
  Nip65Fetcher nip65,
  DmRelaysFetcher dmRelays,
  BlossomServersFetcher blossomServers,
) {
  for (final (name, fetcher) in [
    ('dmRelays', dmRelays),
    ('blossomServers', blossomServers),
  ]) {
    if (!identical(fetcher.nip65Fetcher, nip65)) {
      throw ArgumentError.value(
        fetcher,
        name,
        'does not find write relays with nip65',
      );
    }
  }
}

Stream<UrlListLookup> _watchUrls(
  String pubkey,
  Stream<Nip01Event> Function(String pubKey) watch,
  Future<EventLookup> Function(String pubKey) lookup,
  List<String> Function(Nip01Event list) urlsOf,
) {
  // taken together: once ended, a lookup with checks is not reused
  final result = lookup(pubkey)..ignore();
  final versions = watch(
    pubkey,
  ).map<UrlListLookup>((list) => UrlListLookup.found(urlsOf(list)));
  return versions.concatWith([
    Stream.fromFuture(result).expand(
      (lookup) => switch (lookup) {
        EventFound() => const <UrlListLookup>[],
        EventNotFound() => const [UrlListLookup.notFound()],
        EventUnavailable(:final reason) => [UrlListLookup.unavailable(reason)],
      },
    ),
  ]);
}

UrlListLookup _urls(
  EventLookup lookup,
  List<String> Function(Nip01Event list) urlsOf,
) => switch (lookup) {
  EventFound(:final event) => UrlListLookup.found(urlsOf(event)),
  EventNotFound() => const UrlListLookup.notFound(),
  EventUnavailable(:final reason) => UrlListLookup.unavailable(reason),
};
