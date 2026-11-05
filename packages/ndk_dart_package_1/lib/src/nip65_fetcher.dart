import 'package:ndk_core/ndk_core.dart';

import 'home_relays.dart';
import 'replaceable_events.dart';

const int _kind = 10002;

/// Fetches NIP-65 relay lists from [relays], and from the user's home relays
/// when a [homeRelayList] is given.
class Nip65Fetcher {
  final RelayReqs _reqs;
  final List<String> relays;
  final HomeRelayList? homeRelayList;
  final Duration timeout;

  Nip65Fetcher({
    required this._reqs,
    this.relays = defaultIndexerRelays,
    this.homeRelayList,
    this.timeout = const Duration(seconds: 5),
  });

  /// Each `kind:10002` event of [pubKey] (hex) found on [relays] and on its
  /// home relays, as soon as it arrives, if newer than the ones before it.
  Stream<Nip01Event> watch(String pubKey) => newerVersions(
    askReplaceable(
      _reqs,
      kind: _kind,
      pubKey: pubKey,
      relays: [...relays, ...?homeRelayList?.homeRelaysOf(pubKey)],
      name: 'nip65',
      timeout: timeout,
    ),
    kind: _kind,
    pubKey: pubKey,
  );

  /// The newest `kind:10002` event of [pubKey] (hex) found on [relays] and on
  /// its home relays, or null if none has one.
  Future<Nip01Event?> fetch(String pubKey) => lastVersion(watch(pubKey));
}

/// The normalized write relays of [relayList], a `kind:10002`: the `r` tags
/// not marked `read`, since NIP-65 makes an unmarked relay both.
List<String> writeRelaysOf(Nip01Event relayList) => cleanRelayUrls([
  for (final tag in relayList.tags)
    if (tag.length > 1 && tag[0] == 'r' && (tag.length < 3 || tag[2] != 'read'))
      tag[1],
]).toSet().toList();
