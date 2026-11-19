import 'nip65_fetcher.dart';
import 'replaceable_fetcher.dart';
import 'replaceable_lookup.dart';

/// Fetches users' [kind] replaceable events, or addressable ones named
/// [dTag], from their write relays, which [nip65Fetcher] finds, and from
/// [relays].
///
/// NIP-65 puts them on the write relays, asked as soon as a relay list
/// arrives. [relays] are asked meanwhile, since many clients also publish
/// there.
class OutboxFetcher extends ReplaceableFetcher {
  final Nip65Fetcher? nip65Fetcher;

  OutboxFetcher({
    required super.reqs,
    required super.kind,
    super.dTag,
    this.nip65Fetcher,
    super.relays,
    super.timeout,
    super.cache,
    super.checks,
    super.maxAge,
    super.batchWindow,
    String? name,
  }) : super(name: name ?? 'kind-$kind');

  /// The write relays [nip65Fetcher] finds for [pubkey]. While no relay
  /// answers it they stay unknown, and [relays] lacking the event does not
  /// make it [EventNotFound].
  @override
  EventLocation locate(String pubkey) {
    final nip65Fetcher = this.nip65Fetcher;
    if (nip65Fetcher == null) {
      return (
        relays: const [],
        found: const Stream.empty(),
        unlocated: Future.value(),
      );
    }
    final relayList = nip65Fetcher.lookup(pubkey);
    return (
      relays: const [],
      found: nip65Fetcher.watch(pubkey).map(writeRelaysOf),
      unlocated: relayList.then(
        (lookup) => switch (lookup) {
          EventUnavailable(:final reason) => 'relay list unavailable: $reason',
          _ => null,
        },
      ),
    );
  }

  /// Sends now the REQs for the relay lists of [pubkeys]: their lookups
  /// started those this one reuses.
  @override
  void locateAll(List<String> pubkeys) =>
      nip65Fetcher?.lookupAll(pubkeys).ignore();
}
