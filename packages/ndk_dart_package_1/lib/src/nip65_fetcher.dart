import 'package:ndk_core/ndk_core.dart';
import 'package:rxdart/rxdart.dart';

import 'home_relays.dart';
import 'replaceable_events.dart';

const int _kind = 10002;

/// Fetches NIP-65 relay lists from [relays], and from the user's home relays
/// when a [homeRelayList] is given.
///
/// The fetchers given the same [Nip65Fetcher] share its lookups.
class Nip65Fetcher {
  final RelayReqs _reqs;
  final List<String> relays;
  final HomeRelayList? homeRelayList;
  final Duration timeout;

  /// How long the result of a finished lookup is reused, the same as ndk's
  /// refresh of users' relay lists.
  final Duration maxAge;

  final Map<String, _Lookup> _lookups = {};

  Nip65Fetcher({
    required this._reqs,
    this.relays = defaultIndexerRelays,
    this.homeRelayList,
    this.timeout = const Duration(seconds: 5),
    this.maxAge = const Duration(minutes: 10),
  });

  /// Each `kind:10002` event of [pubKey] (hex) found on [relays] and on its
  /// home relays, as soon as it arrives, if newer than the ones before it.
  ///
  /// A lookup still running, or finished less than [maxAge] ago, is reused,
  /// starting on the newest list it found so far. Once started, a lookup runs
  /// until every relay answered or [timeout], even with no one listening.
  Stream<Nip01Event> watch(String pubKey) {
    final lookup = _lookups[pubKey];
    if (lookup != null && !lookup.isStale) return lookup.versions;
    return (_lookups[pubKey] = _Lookup(_ask(pubKey), maxAge)).versions;
  }

  /// The newest `kind:10002` event of [pubKey] (hex) found on [relays] and on
  /// its home relays, or null if none has one.
  Future<Nip01Event?> fetch(String pubKey) => lastVersion(watch(pubKey));

  Stream<Nip01Event> _ask(String pubKey) => newerVersions(
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
}

class _Lookup {
  late final Stream<Nip01Event> versions;
  DateTime? _staleAt;

  _Lookup(Stream<Nip01Event> source, Duration maxAge) {
    versions = source
        .doOnDone(() => _staleAt = DateTime.now().add(maxAge))
        .publishReplay(maxSize: 1)
        .autoConnect();
  }

  bool get isStale {
    final staleAt = _staleAt;
    return staleAt != null && !DateTime.now().isBefore(staleAt);
  }
}

/// The normalized write relays of [relayList], a `kind:10002`: the `r` tags
/// not marked `read`, since NIP-65 makes an unmarked relay both.
List<String> writeRelaysOf(Nip01Event relayList) => cleanRelayUrls([
  for (final tag in relayList.tags)
    if (tag.length > 1 && tag[0] == 'r' && (tag.length < 3 || tag[2] != 'read'))
      tag[1],
]).toSet().toList();
