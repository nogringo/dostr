import 'package:ndk_core/ndk_core.dart';
import 'package:rxdart/rxdart.dart';

import 'nip65_fetcher.dart';
import 'replaceable_events.dart';

const int _kind = 0;

/// Fetches users' `kind:0` metadata from their write relays, which
/// [nip65Fetcher] finds, and from [relays].
class MetadataFetcher {
  final RelayReqs _reqs;
  final Nip65Fetcher? nip65Fetcher;
  final List<String> relays;
  final Duration timeout;

  MetadataFetcher({
    required this._reqs,
    this.nip65Fetcher,
    this.relays = defaultIndexerRelays,
    this.timeout = const Duration(seconds: 5),
  });

  /// Each `kind:0` event of [pubKey] (hex) found on its write relays and on
  /// [relays], as soon as it arrives, if newer than the ones before it.
  ///
  /// NIP-65 puts it on the write relays, asked as soon as a relay list
  /// arrives. [relays] are asked meanwhile, since many clients also publish it
  /// to indexers. Each relay is asked once.
  Stream<Nip01Event> watch(String pubKey) {
    final asked = <String>{};
    Stream<Nip01Event> ask(List<String> urls) => askReplaceable(
      _reqs,
      kind: _kind,
      pubKey: pubKey,
      relays: [
        for (final url in cleanRelayUrls(urls))
          if (asked.add(url)) url,
      ],
      name: 'metadata',
      timeout: timeout,
    );

    return newerVersions(
      MergeStream([
        ask(relays),
        ?nip65Fetcher
            ?.watch(pubKey)
            .flatMap((relayList) => ask(writeRelaysOf(relayList))),
      ]),
      kind: _kind,
      pubKey: pubKey,
    );
  }

  /// The newest `kind:0` event of [pubKey] (hex) found on its write relays
  /// and on [relays], or null if none has one.
  Future<Nip01Event?> fetch(String pubKey) => lastVersion(watch(pubKey));
}
