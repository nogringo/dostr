import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_home_relays/dostr_home_relays.dart';

import 'replaceable_fetcher.dart';

/// Fetches NIP-65 relay lists, `kind:10002`, from [relays], and from the
/// user's home relays when a [homeRelayList] is given.
///
/// The fetchers given the same [Nip65Fetcher] share its lookups.
class Nip65Fetcher extends ReplaceableFetcher {
  final HomeRelayList? homeRelayList;

  Nip65Fetcher({
    required super.reqs,
    super.relays,
    this.homeRelayList,
    super.timeout,
    super.cache,
    super.checks,
    super.maxAge,
    super.batchWindow,
  }) : super(kind: 10002, name: 'nip65');

  /// The home relays of [pubkey], asked with [relays].
  @override
  EventLocation locate(String pubkey) => (
    relays: homeRelayList?.homeRelaysOf(pubkey) ?? const [],
    found: const Stream.empty(),
    unlocated: Future.value(),
  );
}

/// The normalized write relays of [relayList], a `kind:10002`: the `r` tags
/// not marked `read`, since NIP-65 makes an unmarked relay both.
List<RelayUrl> writeRelaysOf(Nip01Event relayList) =>
    _relaysOf(relayList, except: 'read');

/// The normalized read relays of [relayList], a `kind:10002`: the `r` tags
/// not marked `write`.
List<RelayUrl> readRelaysOf(Nip01Event relayList) =>
    _relaysOf(relayList, except: 'write');

/// Every normalized relay of [relayList], a `kind:10002`, whatever its marker.
List<RelayUrl> allRelaysOf(Nip01Event relayList) => _relaysOf(relayList);

List<RelayUrl> _relaysOf(Nip01Event relayList, {String? except}) => {
  for (final tag in relayList.tags)
    if (tag.length > 1 &&
        tag[0] == 'r' &&
        (except == null || tag.length < 3 || tag[2] != except))
      ?RelayUrl.tryParse(tag[1]),
}.toList();
