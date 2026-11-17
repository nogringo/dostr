import 'dart:collection';
import 'dart:math';

import '../connections/relay_connection.dart';
import '../connections/relay_connection_key.dart';
import '../helpers/logger.dart';
import 'request_state.dart';

/// A request waiting for a slot on a connection. [order] tells which came
/// first.
typedef _Queued = ({int order, RequestState state, RelayRequestState request});

/// The requests waiting for a slot on one connection.
///
/// Queries and subscriptions wait in separate queues. A subscription held back
/// by its share is then passed over without scanning the queries behind it.
class _Waiting {
  final queries = Queue<_Queued>();
  final subscriptions = Queue<_Queued>();

  bool get isEmpty => queries.isEmpty && subscriptions.isEmpty;

  Queue<_Queued> of(RequestState state) =>
      state.isSubscription ? subscriptions : queries;
}

/// The REQs held back while their connection is full. Internal to dostr_core.
///
/// Each connection keeps at most as many REQs open as its relay accepts.
class ReqQueue {
  /// the requests in flight, by id, to tell which slots subscriptions hold
  final Map<String, RequestState> _inFlight;

  final Map<RelayConnectionKey, _Waiting> _waiting = {};

  /// every request [_waiting] holds. A request removed from here stays in its
  /// queue until it reaches the head, where it is dropped.
  final Set<RelayRequestState> _queued = Set.identity();

  int _queuedSoFar = 0;

  ReqQueue(this._inFlight);

  bool contains(RelayRequestState request) => _queued.contains(request);

  /// Stops [request] from waiting, and says whether it was.
  bool remove(RelayRequestState request) => _queued.remove(request);

  /// How many of [limit] slots subscriptions may hold.
  ///
  /// A quarter of the slots, and at least one, stays with queries, unless
  /// there is a single slot. strfry limits stored queries and live
  /// subscriptions apart, so a connection full of subscriptions still answers
  /// queries.
  static int _subscriptionShare(int limit) =>
      limit < 2 ? limit : limit - max(1, limit ~/ 4);

  int _subscriptionsIn(Set<String> slots) =>
      slots.where((id) => _inFlight[id]?.isSubscription ?? false).length;

  /// Queues [request] when [connection] has no slot for it right now, and
  /// says whether it did.
  bool holdBack(
    RelayConnection connection,
    RequestState state,
    RelayRequestState request,
  ) {
    final limit = connection.limits.subscriptions;
    var heldByShare = false;
    if (limit != null && connection.isConnected) {
      final slots = connection.slots.held;
      heldByShare =
          state.isSubscription &&
          _subscriptionsIn(slots) >= _subscriptionShare(limit);
      if (slots.length < limit && !heldByShare) return false;
    }
    if (heldByShare) {
      logger.warning(
        () =>
            "REQ ${state.id} waits on ${connection.key}: subscriptions hold "
            "${_subscriptionShare(limit!)} of its $limit slots",
      );
    } else {
      logger.fine(
        () => "REQ ${state.id} waits for a slot on ${connection.key}",
      );
    }
    _waiting.putIfAbsent(connection.key, _Waiting.new).of(state).add((
      order: _queuedSoFar++,
      state: state,
      request: request,
    ));
    _queued.add(request);
    return true;
  }

  /// Hands to [write], oldest first, the requests waiting on [connection]
  /// that now fit there.
  void admit(
    RelayConnection connection,
    void Function(RequestState state, RelayRequestState request) write,
  ) {
    final waiting = _waiting[connection.key];
    final limit = connection.limits.subscriptions;
    if (waiting == null || limit == null || !connection.isConnected) return;
    final slots = connection.slots.held;
    final share = _subscriptionShare(limit);
    var held = slots.length;
    var subscriptions = _subscriptionsIn(slots);
    while (held < limit) {
      final query = _head(waiting.queries);
      final subscription = subscriptions < share
          ? _head(waiting.subscriptions)
          : null;
      final next = query == null
          ? subscription
          : subscription == null || query.order < subscription.order
          ? query
          : subscription;
      if (next == null) break;
      waiting.of(next.state).removeFirst();
      _queued.remove(next.request);
      if (connection.slots.holds(next.state.id)) continue;
      held++;
      if (next.state.isSubscription) subscriptions++;
      write(next.state, next.request);
    }
    if (waiting.isEmpty && identical(_waiting[connection.key], waiting)) {
      _waiting.remove(connection.key);
    }
  }

  /// The first request of [queue] still waiting, once those that stopped
  /// waiting are dropped.
  _Queued? _head(Queue<_Queued> queue) {
    while (queue.isNotEmpty) {
      final entry = queue.first;
      if (_queued.contains(entry.request) &&
          !entry.state.isOver &&
          !entry.request.isDone) {
        return entry;
      }
      queue.removeFirst();
      _queued.remove(entry.request);
    }
    return null;
  }

  /// Drops every request waiting on [key].
  void drop(RelayConnectionKey key) {
    final waiting = _waiting.remove(key);
    if (waiting == null) return;
    for (final entry in [...waiting.queries, ...waiting.subscriptions]) {
      _queued.remove(entry.request);
    }
  }
}
