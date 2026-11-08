import 'dart:async';
import 'dart:math';

import 'package:ndk_core/ndk_core.dart';
import 'package:rxdart/rxdart.dart';

const Duration defaultBatchWindow = Duration(milliseconds: 50);

/// The lowest NIP-11 `max_limit` seen (relay.nostr.net), so a relay that
/// clamps `limit` still returns every author.
const int maxAuthorsPerFilter = 100;

/// About 61 KB of REQ: under 65,535 bytes, half the 131,072 strfry enforces,
/// and under the 10 filters nostream accepts by default.
const int maxFiltersPerReq = 9;

/// Asks relays for the newest [kind] event of pubkeys, named [dTag] if
/// addressable. The pubkeys asked within [window] share the REQs of each
/// relay: up to [maxFiltersPerReq] filters of up to [maxAuthorsPerFilter]
/// authors, each filter's `limit` their number, since a relay returns only
/// the latest version of each (NIP-01). A relay that closes a REQ gets each
/// of its filters alone, then each pubkey, unless its CLOSED refuses a REQ
/// whatever its size.
class ReplaceableAsks {
  final RelayReqs _reqs;
  final int kind;
  final String? dTag;
  final String name;
  final Duration timeout;
  final Duration window;

  /// The waiters of the next REQs, by relay url, then by pubkey.
  final Map<String, Map<String, List<_Waiter>>> _pending = {};
  Timer? _windowEnd;

  ReplaceableAsks(
    this._reqs, {
    required this.kind,
    this.dTag,
    required this.name,
    required this.timeout,
    required this.window,
  });

  /// What [relays] send for the newest event of [pubKey] (hex). [pubKey]
  /// joins the next REQs right away, which go out at most [window] later,
  /// and each runs until its relay answered or [timeout]. Once they ended,
  /// [outcomes] gets what each relay did.
  Stream<Nip01Event> ask(
    String pubKey, {
    required Iterable<String> relays,
    Map<String, RelayRequestOutcome>? outcomes,
  }) {
    final urls = {for (final url in relays) ?cleanRelayUrl(url)};
    return _answers({
      for (final url in urls) url: _wait(url, pubKey),
    }, outcomes);
  }

  /// Sends the next REQs now, without waiting for the end of [window].
  void flush() {
    _windowEnd?.cancel();
    _windowEnd = null;
    for (final MapEntry(key: url, value: byPubKey) in _pending.entries) {
      final lots = [
        for (final chunk in _chunks(byPubKey.entries, maxAuthorsPerFilter))
          Map.fromEntries(chunk),
      ];
      for (final req in _chunks(lots, maxFiltersPerReq)) {
        unawaited(_send(url, req));
      }
    }
    _pending.clear();
  }

  Stream<Nip01Event> _answers(
    Map<String, _Waiter> waiters,
    Map<String, RelayRequestOutcome>? outcomes,
  ) async* {
    if (waiters.isEmpty) return;
    yield* MergeStream([
      for (final waiter in waiters.values) waiter.events.stream,
    ]);
    for (final MapEntry(key: url, value: waiter) in waiters.entries) {
      if (waiter.outcome case final outcome?) outcomes?[url] = outcome;
    }
  }

  _Waiter _wait(String url, String pubKey) {
    if (_pending.isEmpty) _windowEnd = Timer(window, flush);
    final waiter = _Waiter();
    ((_pending[url] ??= {})[pubKey] ??= []).add(waiter);
    return waiter;
  }

  Future<void> _send(String url, List<_Lot> lots) async {
    final byPubKey = {for (final lot in lots) ...lot};
    final waiters = [for (final list in byPubKey.values) ...list];
    try {
      final req = _reqs.req(
        relays: {
          url: [
            for (final lot in lots)
              Filter(
                kinds: [kind],
                authors: lot.keys.toList(),
                dTags: dTag == null ? null : [dTag!],
                limit: lot.length,
              ),
          ],
        },
        name: name,
        timeout: timeout,
      );
      await for (final received in req.events) {
        for (final waiter in byPubKey[received.event.pubKey] ?? const []) {
          waiter.events.add(received.event);
        }
      }
      final outcome = (await req.done)[url];
      if (byPubKey.length > 1 && _mayBeTooBig(outcome)) {
        await Future.wait([
          for (final smaller in _smaller(lots)) _send(url, smaller),
        ]);
        return;
      }
      for (final waiter in waiters) {
        waiter.outcome = outcome;
      }
    } catch (error, stackTrace) {
      for (final waiter in waiters) {
        if (!waiter.events.isClosed) waiter.events.addError(error, stackTrace);
      }
    } finally {
      for (final waiter in waiters) {
        unawaited(waiter.events.close());
      }
    }
  }
}

/// The waiters of the pubkeys one filter asks for, by pubkey.
typedef _Lot = Map<String, List<_Waiter>>;

List<List<T>> _chunks<T>(Iterable<T> items, int size) {
  final list = items.toList();
  return [
    for (var i = 0; i < list.length; i += size)
      list.sublist(i, min(i + size, list.length)),
  ];
}

/// The REQs that ask again for what [lots] asked: one per lot, then one per
/// pubkey.
List<List<_Lot>> _smaller(List<_Lot> lots) => lots.length > 1
    ? [
        for (final lot in lots) [lot],
      ]
    : [
        for (final entry in lots.single.entries)
          [
            Map.fromEntries([entry]),
          ],
      ];

/// The NIP-01 CLOSED prefixes that refuse a REQ whatever its size.
const _refusalsOfAnySize = [
  'auth-required',
  'restricted',
  'rate-limited',
  'blocked',
];

/// Whether a relay may have closed a REQ for its size.
bool _mayBeTooBig(RelayRequestOutcome? outcome) => switch (outcome) {
  RelayRequestOutcome(status: RelayRequestStatus.closed, :final message) =>
    !_refusalsOfAnySize.any((prefix) => message?.startsWith(prefix) ?? false),
  _ => false,
};

class _Waiter {
  final events = StreamController<Nip01Event>();
  RelayRequestOutcome? outcome;
}
