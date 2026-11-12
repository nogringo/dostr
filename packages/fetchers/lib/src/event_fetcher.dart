import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_url_set/dostr_url_set.dart';

/// Fetches the events of any filter from the relays a [UrlSet] resolves to,
/// each asked as soon as a list names it.
class EventFetcher {
  final RelayReqs _reqs;

  /// Watches the lists the sets read, such as [fetcherUrlListWatchFn] does.
  final UrlListWatchFn urlLists;

  /// How long each relay has to answer, from when it is asked.
  final Duration timeout;

  /// Only shows in logs.
  final String name;

  EventFetcher({
    required RelayReqs reqs,
    required this.urlLists,
    this.timeout = const Duration(seconds: 5),
    this.name = 'events',
  }) : _reqs = reqs;

  /// Asks each relay [from] resolves to for the events matching [filter],
  /// once, as soon as a list names it, with its own REQ and [timeout]. A
  /// relay a later snapshot of [from] drops was still asked.
  ///
  /// Each relay applies the `limit` of [filter] on its own, so more events
  /// may come in all.
  EventFetch fetch(Filter filter, {required UrlSet from}) {
    if (from.kinds.contains(UrlListKind.blossom)) {
      throw ArgumentError.value(
        from.toMap(),
        'from',
        'names Blossom servers, not relays',
      );
    }
    return EventFetch._(this, filter.clone(), from);
  }
}

/// One fetch started by [EventFetcher.fetch].
class EventFetch {
  final EventFetcher _fetcher;
  final Filter _filter;
  late final StreamController<Nip01Event> _events = StreamController(
    onCancel: close,
  );
  final _done = Completer<EventFetchResult>();
  late final StreamSubscription<UrlSetSnapshot> _snapshots;
  UrlSetSnapshot? _last;
  final Set<String> _asked = {};
  final Map<String, RelayReq> _running = {};
  final Map<String, RelayRequestOutcome> _outcomes = {};
  final List<Nip01Event> _received = [];
  final Set<String> _ids = {};
  bool _resolved = false;
  bool _closed = false;

  EventFetch._(this._fetcher, this._filter, UrlSet from) {
    // an error reaches [done] even when only [events] is listened to
    _done.future.ignore();
    _snapshots = watchUrlSet(from, _fetcher.urlLists).listen(
      _ask,
      onError: _fail,
      onDone: () {
        _resolved = true;
        _endIfOver();
      },
    );
  }

  /// Each event matching the filter, once, as soon as a relay sends it.
  /// Single-subscription: cancelling it closes the fetch, like [close].
  Stream<Nip01Event> get events => _events.stream;

  /// How the fetch ended, once the set resolved and every relay asked
  /// answered or timed out, or once it was closed.
  Future<EventFetchResult> get done => _done.future;

  /// Stops resolving the set and closes the REQs still running. [done] then
  /// gives what came so far.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _resolved = true;
    await _snapshots.cancel();
    await Future.wait([for (final req in _running.values) req.close()]);
    _endIfOver();
  }

  void _ask(UrlSetSnapshot snapshot) {
    _last = snapshot;
    for (final url in snapshot.urls) {
      final relay = cleanRelayUrl(url);
      if (relay == null || !_asked.add(relay)) continue;
      final req = _fetcher._reqs.req(
        relays: {
          relay: [_filter],
        },
        name: _fetcher.name,
        timeout: _fetcher.timeout,
      );
      _running[relay] = req;
      req.events.listen(
        (received) => _receive(received.event),
        onDone: () async {
          _outcomes.addAll(await req.done);
          _running.remove(relay);
          _endIfOver();
        },
      );
    }
  }

  void _receive(Nip01Event event) {
    if (_done.isCompleted || !_matches(_filter, event) || !_ids.add(event.id)) {
      return;
    }
    _received.add(event);
    _events.add(event);
  }

  void _endIfOver() {
    if (!_resolved || _running.isNotEmpty || _done.isCompleted) return;
    final last = _last;
    final relays = {
      for (final url in last?.urls ?? const <String>[]) ?cleanRelayUrl(url),
    };
    _done.complete(
      EventFetchResult(
        events: List.unmodifiable(_received),
        outcomes: Map.unmodifiable(_outcomes),
        unavailable: last?.unavailable ?? const [],
        complete:
            !_closed &&
            last != null &&
            last.done &&
            last.unavailable.isEmpty &&
            relays.every(
              (relay) => _outcomes[relay]?.status == RelayRequestStatus.eose,
            ),
      ),
    );
    unawaited(_events.close());
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_done.isCompleted) return;
    _done.completeError(error, stackTrace);
    _events.addError(error, stackTrace);
    unawaited(_events.close());
    for (final req in _running.values) {
      unawaited(req.close());
    }
  }
}

/// How an [EventFetch] ended.
final class EventFetchResult {
  /// Each event received, once, in the order it came.
  final List<Nip01Event> events;

  /// What each relay asked did with its REQ, by relay url.
  final Map<String, RelayRequestOutcome> outcomes;

  /// Why each unavailable list of the set is: the relays it names were not
  /// asked.
  final List<String> unavailable;

  /// Whether [events] are all that the relays of the set hold: it resolved
  /// with every list available, and each of its relays sent an EOSE. A closed
  /// fetch is not complete.
  final bool complete;

  const EventFetchResult({
    required this.events,
    required this.outcomes,
    required this.unavailable,
    required this.complete,
  });
}

/// Whether [event] matches [filter], its `search` aside: a relay may send
/// events that do not.
bool _matches(Filter filter, Nip01Event event) {
  if (filter.since case final since? when event.createdAt < since) {
    return false;
  }
  if (filter.until case final until? when event.createdAt > until) {
    return false;
  }
  return (filter.ids?.contains(event.id) ?? true) &&
      (filter.authors?.contains(event.pubKey) ?? true) &&
      (filter.kinds?.contains(event.kind) ?? true) &&
      (filter.tags?.entries.every(
            (wanted) => event.tags.any(
              (tag) =>
                  tag.length > 1 &&
                  tag[0] == wanted.key &&
                  wanted.value.contains(tag[1]),
            ),
          ) ??
          true);
}
