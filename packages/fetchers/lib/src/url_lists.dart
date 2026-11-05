import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_url_set/ndk_url_set.dart';

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

UrlListLookup _urls(
  EventLookup lookup,
  List<String> Function(Nip01Event list) urlsOf,
) => switch (lookup) {
  EventFound(:final event) => UrlListLookup.found(urlsOf(event)),
  EventNotFound() => const UrlListLookup.notFound(),
  EventUnavailable(:final reason) => UrlListLookup.unavailable(reason),
};
