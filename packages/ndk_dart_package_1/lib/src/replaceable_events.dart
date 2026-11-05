import 'package:ndk_core/ndk_core.dart';

/// Relays that index users' `kind:0` and `kind:10002` events, the same as
/// ndk's bootstrap relays.
const List<String> defaultIndexerRelays = [
  'wss://purplepag.es',
  'wss://relay.primal.net',
  'wss://relay.ditto.pub',
];

/// What [relays] send for the newest [kind] event of [pubKey] (hex), named
/// [dTag] if addressable, until each of them answered or [timeout]. The REQ
/// opens on listen.
Stream<Nip01Event> askReplaceable(
  RelayReqs reqs, {
  required int kind,
  required String pubKey,
  String? dTag,
  required Iterable<String> relays,
  required String name,
  required Duration timeout,
}) async* {
  final filter = Filter(
    kinds: [kind],
    authors: [pubKey],
    dTags: dTag == null ? null : [dTag],
    limit: 1,
  );
  final req = reqs.req(
    relays: {
      for (final url in relays) url: [filter],
    },
    name: name,
    timeout: timeout,
  );
  yield* req.events.map((received) => received.event);
}

/// The [kind] events of [pubKey] among [events], named [dTag] if addressable,
/// each newer than the ones before it, the lowest id winning a tie (NIP-01).
///
/// Not an `async*`: one waiting in `await for` only stops on its next event,
/// so cancelling it would wait for the slowest relay.
Stream<Nip01Event> newerVersions(
  Stream<Nip01Event> events, {
  required int kind,
  required String pubKey,
  String? dTag,
}) {
  Nip01Event? newest;
  return events
      // a relay may send events that do not match the filter
      .where(
        (event) =>
            event.kind == kind &&
            event.pubKey == pubKey &&
            (dTag == null || event.getDtag() == dTag),
      )
      .where((event) {
        final current = newest;
        if (current != null && !_replaces(event, current)) return false;
        newest = event;
        return true;
      });
}

/// The last of [versions], so the newest, or null if there is none.
Future<Nip01Event?> lastVersion(Stream<Nip01Event> versions) =>
    versions.fold(null, (_, version) => version);

bool _replaces(Nip01Event event, Nip01Event current) =>
    event.createdAt > current.createdAt ||
    (event.createdAt == current.createdAt &&
        event.id.compareTo(current.id) < 0);
