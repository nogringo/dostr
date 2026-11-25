import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:rxdart/rxdart.dart';

import 'blossom_servers_fetcher.dart';
import 'dm_relays_fetcher.dart';
import 'nip65_fetcher.dart';
import 'outbox_fetcher.dart';
import 'private_relays_fetcher.dart';
import 'replaceable_fetcher.dart';
import 'replaceable_lookup.dart';

/// A [UrlListFn] that reads the lists with these fetchers, their cache and
/// checks included.
///
/// [dmRelays], [blossomServers] and [privateRelays] find the write relays
/// with [nip65], which must be their `nip65Fetcher`. A private relay list
/// (kind 10013) its owner has no signer here to decrypt is unavailable, and
/// without [privateRelays] it throws an [UnsupportedError].
UrlListFn fetcherUrlListFn({
  required Nip65Fetcher nip65,
  required DmRelaysFetcher dmRelays,
  required BlossomServersFetcher blossomServers,
  PrivateRelaysFetcher? privateRelays,
}) {
  _requireNip65(nip65, {
    'dmRelays': dmRelays,
    'blossomServers': blossomServers,
    'privateRelays': privateRelays,
  });
  return (pubkey, kind) async => switch (kind) {
    UrlListKind.outbox => _urls(await nip65.lookup(pubkey), writeRelaysOf),
    UrlListKind.inbox => _urls(await nip65.lookup(pubkey), readRelaysOf),
    UrlListKind.nip65 => _urls(await nip65.lookup(pubkey), allRelaysOf),
    UrlListKind.dm => _urls(await dmRelays.lookup(pubkey), dmRelaysOf),
    UrlListKind.blossom => _urls(
      await blossomServers.lookup(pubkey),
      blossomServersOf,
    ),
    UrlListKind.private => await _privateUrls(
      pubkey,
      privateRelays ?? (throw _noPrivateRelays),
    ),
  };
}

/// A [UrlListWatchFn] for [watchUrlSet] that watches the lists with these
/// fetchers, their cache and checks included: each version they find comes
/// as found, the cached one first.
///
/// [dmRelays], [blossomServers] and [privateRelays] ask the write relays as
/// soon as [nip65] finds them. Each private relay list version comes once
/// decrypted, and the list is unavailable when none could be. Without
/// [privateRelays], a private relay list (kind 10013) emits an
/// [UnsupportedError].
UrlListWatchFn fetcherUrlListWatchFn({
  required Nip65Fetcher nip65,
  required DmRelaysFetcher dmRelays,
  required BlossomServersFetcher blossomServers,
  PrivateRelaysFetcher? privateRelays,
}) {
  _requireNip65(nip65, {
    'dmRelays': dmRelays,
    'blossomServers': blossomServers,
    'privateRelays': privateRelays,
  });
  return (pubkey, kind) => switch (kind) {
    UrlListKind.outbox => _watchUrls(pubkey, nip65, writeRelaysOf),
    UrlListKind.inbox => _watchUrls(pubkey, nip65, readRelaysOf),
    UrlListKind.nip65 => _watchUrls(pubkey, nip65, allRelaysOf),
    UrlListKind.dm => _watchUrls(pubkey, dmRelays, dmRelaysOf),
    UrlListKind.blossom => _watchUrls(pubkey, blossomServers, blossomServersOf),
    UrlListKind.private =>
      privateRelays == null
          ? Stream.error(_noPrivateRelays)
          : _watchPrivateUrls(pubkey, privateRelays),
  };
}

UnsupportedError get _noPrivateRelays =>
    UnsupportedError('private relay lists need a privateRelays fetcher');

void _requireNip65(Nip65Fetcher nip65, Map<String, OutboxFetcher?> fetchers) {
  for (final MapEntry(key: name, value: fetcher) in fetchers.entries) {
    if (fetcher != null && !identical(fetcher.nip65Fetcher, nip65)) {
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
  ReplaceableFetcher fetcher,
  List<String> Function(Nip01Event list) urlsOf,
) {
  // taken together: once ended, a lookup with checks is not reused
  final result = fetcher.lookup(pubkey)..ignore();
  final versions = fetcher
      .watch(pubkey)
      .map<UrlListLookup>((list) => UrlListLookup.found(urlsOf(list)));
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

Future<UrlListLookup> _privateUrls(
  String pubkey,
  PrivateRelaysFetcher fetcher,
) async => switch (await fetcher.lookup(pubkey)) {
  EventFound(:final event) => await _decryptedUrls(fetcher, event),
  EventNotFound() => const UrlListLookup.notFound(),
  EventUnavailable(:final reason) => UrlListLookup.unavailable(reason),
};

Stream<UrlListLookup> _watchPrivateUrls(
  String pubkey,
  PrivateRelaysFetcher fetcher,
) {
  final result = fetcher.lookup(pubkey)..ignore();
  var decrypted = false;
  UrlListLookup? failure;
  final versions = fetcher
      .watch(pubkey)
      .asyncMap((list) => _decryptedUrls(fetcher, list))
      .where((lookup) {
        if (lookup is UrlListUnavailable) {
          failure = lookup;
          return false;
        }
        decrypted = true;
        return true;
      });
  return versions.concatWith([
    Stream.fromFuture(result).expand(
      (lookup) => switch (lookup) {
        EventFound() => [if (!decrypted) ?failure],
        EventNotFound() => const [UrlListLookup.notFound()],
        EventUnavailable(:final reason) => [UrlListLookup.unavailable(reason)],
      },
    ),
  ]);
}

Future<UrlListLookup> _decryptedUrls(
  PrivateRelaysFetcher fetcher,
  Nip01Event list,
) async {
  try {
    return UrlListLookup.found(await fetcher.relaysOf(list));
  } on PrivateRelaysDecryptionException catch (e) {
    return UrlListLookup.unavailable('$e');
  }
}
