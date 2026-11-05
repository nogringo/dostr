import 'package:ndk_core/ndk_core.dart';

const int _kind = 10002;

/// Relays that index `kind:10002` lists, the same as ndk's bootstrap relays.
const List<String> defaultNip65Relays = [
  'wss://purplepag.es',
  'wss://relay.primal.net',
  'wss://relay.ditto.pub',
];

/// Fetches NIP-65 relay lists from [relays].
class Nip65Fetcher {
  final RelayReqs _reqs;
  final List<String> relays;
  final Duration timeout;

  Nip65Fetcher({
    required this._reqs,
    this.relays = defaultNip65Relays,
    this.timeout = const Duration(seconds: 5),
  });

  /// The newest `kind:10002` event of [pubKey] (hex) found on [relays], or
  /// null if none has one.
  Future<Nip01Event?> fetch(String pubKey) async {
    final filter = Filter(kinds: [_kind], authors: [pubKey], limit: 1);
    final req = _reqs.req(
      relays: {
        for (final url in relays) url: [filter],
      },
      name: 'nip65',
      timeout: timeout,
    );

    Nip01Event? newest;
    await for (final RelayReqEvent(:event) in req.events) {
      // a relay may send events that do not match the filter
      if (event.kind != _kind || event.pubKey != pubKey) continue;
      if (newest == null || _replaces(event, newest)) newest = event;
    }
    return newest;
  }

  /// NIP-01: on a tie, the lowest id wins.
  static bool _replaces(Nip01Event event, Nip01Event current) =>
      event.createdAt > current.createdAt ||
      (event.createdAt == current.createdAt &&
          event.id.compareTo(current.id) < 0);
}
