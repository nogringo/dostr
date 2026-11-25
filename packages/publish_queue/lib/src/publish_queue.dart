import 'dart:async';
import 'dart:math';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_url_set/dostr_url_set.dart';

import 'backoff.dart';
import 'publish_queue_store.dart';
import 'publish_slots.dart';
import 'queue_store.dart';
import 'queued_publish.dart';
import 'relay_reachability.dart';
import 'unreachable_relays.dart';

/// Sends [event] to [relays] once and gives what each relay did with it, as
/// `RelayPublishes.publish` of dostr_core does. [account] is the account the
/// event was queued under, see [PublishQueue.publish].
///
/// It must complete: `RelayPublishes.publish` does once its timeout runs out.
/// A relay missing from the result counts as one that did not answer.
typedef PublishFn =
    Future<Map<RelayUrl, RelayPublishOutcome>> Function(
      Nip01Event event,
      List<RelayUrl> relays, {
      String? account,
    });

/// An offline-first queue of events to publish.
///
/// Contract:
///  - `publish(event, relaySet: ...)` persists the event before returning,
///    without touching the network.
///  - A [UrlSet] is resolved by the worker, once, then frozen into the
///    record's relays.
///  - Delivery is guaranteed in the eventual sense: the queue keeps retrying
///    each `pending` entry until every relay has accepted it or refused it for
///    good.
///  - Records are never auto-deleted. A terminal entry stays in the store for
///    manual `republish` or inspection. Explicit removal is available via
///    `remove`, `removeSettled`, `clearLocalAccountData` and
///    `clearAllLocalData`.
class PublishQueue {
  final PublishFn _publishFn;
  final UrlListFn? _relayListFn;
  final QueueStore _store;
  final Duration _tickInterval;
  final Duration _initialBackoff;
  final Duration _maxBackoff;
  final int _maxInaccessibleAttemptsPerRelay;
  final Random _random;
  final int Function() _now;
  final Stream<bool>? _onlineSignal;
  final bool _pauseWhileOffline;
  final PublishSlots _publishSlots;
  final void Function(Object error, StackTrace stackTrace)? _onError;
  final UnreachableRelays _unreachable = UnreachableRelays();

  Timer? _tickTimer;
  StreamSubscription<bool>? _onlineSub;

  /// The latest value of the online signal, null until it emits.
  bool? _isOnline;
  int? _lastAnswerAt;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  /// Keys asked for an attempt while one was in flight.
  final Set<String> _requested = {};
  final Set<Future<void>> _scans = {};
  bool _disposed = false;
  final Completer<void> _disposal = Completer<void>();

  PublishQueue._({
    required PublishFn publishFn,
    required UrlListFn? relayListFn,
    required PublishQueueStore store,
    required Duration tickInterval,
    required Duration initialBackoff,
    required Duration maxBackoff,
    required int maxInaccessibleAttemptsPerRelay,
    required int maxConcurrentPublishes,
    required Stream<bool>? onlineSignal,
    required bool pauseWhileOffline,
    required void Function(Object error, StackTrace stackTrace)? onError,
    Random? random,
    int Function()? now,
  }) : _publishFn = publishFn,
       _relayListFn = relayListFn,
       _store = QueueStore(store),
       _tickInterval = tickInterval,
       _initialBackoff = initialBackoff,
       _maxBackoff = maxBackoff,
       _maxInaccessibleAttemptsPerRelay = maxInaccessibleAttemptsPerRelay,
       _onlineSignal = onlineSignal,
       _pauseWhileOffline = pauseWhileOffline,
       _publishSlots = PublishSlots(maxConcurrentPublishes),
       _onError = onError,
       _random = random ?? Random(),
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (maxInaccessibleAttemptsPerRelay <= 0) {
      throw ArgumentError.value(
        maxInaccessibleAttemptsPerRelay,
        'maxInaccessibleAttemptsPerRelay',
        'must be greater than zero',
      );
    }
    if (maxConcurrentPublishes <= 0) {
      throw ArgumentError.value(
        maxConcurrentPublishes,
        'maxConcurrentPublishes',
        'must be greater than zero',
      );
    }
  }

  /// A queue that sends with [publishFn], for tests or for callers who
  /// publish their own way.
  ///
  /// [store] keeps the records between runs, and serves this queue alone, see
  /// [PublishQueueStore].
  ///
  /// Pass [onlineSignal] to make the periodic retry loop connectivity-aware:
  /// while the latest emission is `false`, periodic ticks are no-ops, and the
  /// `false -> true` edge triggers an immediate retry pass. `retryNow()`
  /// always runs regardless of this signal.
  ///
  /// [maxInaccessibleAttemptsPerRelay] caps consecutive online attempts where
  /// a relay is unreachable for one event. Once reached, that relay is treated
  /// as terminally failed for the event. An attempt counts as online when one
  /// of the queue's relays answered while it ran, or when [onlineSignal] said
  /// so both when it started and when it ended: without [onlineSignal], a
  /// relay is only cut off while other relays answer. Exceptions thrown by
  /// [publishFn] never count. An attempt [onlineSignal] shows offline is
  /// retried after [initialBackoff] without growing the backoff.
  ///
  /// A relay found unreachable while online is not tried again before its
  /// backoff runs out, whatever the event: the other events owed to it skip
  /// it meanwhile and take its count of unreachable attempts. So a dead relay
  /// is tried once a round, not once per event.
  ///
  /// [maxConcurrentPublishes] caps the attempts publishing at once. The others
  /// wait their turn, due entries in the order they were queued, so a backlog
  /// piled up offline goes out in order rather than all at once.
  ///
  /// [relayListFn] resolves the relay lists a [UrlSet] refers to, such as
  /// `fetcherUrlListFn` of dostr_fetchers. Without it, only sets that need no
  /// lookup can be published. The queue puts no timeout on it: bound the
  /// network part yourself, and let a signer take as long as it needs.
  ///
  /// [onError] gets the errors of the work the queue does in the background,
  /// such as a write the store refuses: the record stays as last stored and
  /// is tried again. Without it, they are uncaught errors of the zone.
  PublishQueue({
    required PublishFn publishFn,
    UrlListFn? relayListFn,
    required PublishQueueStore store,
    Duration tickInterval = const Duration(seconds: 30),
    Duration initialBackoff = const Duration(seconds: 5),
    Duration maxBackoff = const Duration(minutes: 30),
    int maxInaccessibleAttemptsPerRelay = 12,
    int maxConcurrentPublishes = 10,
    Stream<bool>? onlineSignal,
    void Function(Object error, StackTrace stackTrace)? onError,
    Random? random,
    int Function()? now,
  }) : this._(
         publishFn: publishFn,
         relayListFn: relayListFn,
         store: store,
         tickInterval: tickInterval,
         initialBackoff: initialBackoff,
         maxBackoff: maxBackoff,
         maxInaccessibleAttemptsPerRelay: maxInaccessibleAttemptsPerRelay,
         maxConcurrentPublishes: maxConcurrentPublishes,
         onlineSignal: onlineSignal,
         pauseWhileOffline: true,
         onError: onError,
         random: random,
         now: now,
       );

  /// A queue that publishes through [relayManager], each attempt waiting
  /// [publishTimeout] for the relays, NIP-42 authentication aside.
  ///
  /// [authPolicyOf] gives the `AuthPolicy` of each publish from the event and
  /// the account it was queued under; null publishes as dostr_core does by
  /// default. Do not authenticate a gift wrap (kind 1059) as its sender: that
  /// tells the recipient's relay who wrote to them.
  ///
  /// Without [onlineSignal], the queue reads the network from the connections
  /// of [relayManager]: online once a public relay is connected, offline once
  /// every connection to one failed or dropped. Loopback, private IPv4 and
  /// IPv6, and `.local` hosts are left out, so a connected dev relay does not
  /// mask an outage. Since dostr_core closes idle connections, having none
  /// tells nothing, so this signal never pauses the periodic retries: it only
  /// keeps offline attempts from counting towards
  /// [maxInaccessibleAttemptsPerRelay]. Pass the platform's connectivity as
  /// [onlineSignal] to pause them, as the default constructor does.
  ///
  /// The other parameters are those of the default constructor.
  factory PublishQueue.withDostr(
    RelayManager relayManager, {
    required PublishQueueStore store,
    UrlListFn? relayListFn,
    AuthPolicy? Function(Nip01Event event, String? account)? authPolicyOf,
    Duration publishTimeout = defaultPublishTimeout,
    Stream<bool>? onlineSignal,
    Duration tickInterval = const Duration(seconds: 30),
    Duration initialBackoff = const Duration(seconds: 5),
    Duration maxBackoff = const Duration(minutes: 30),
    int maxInaccessibleAttemptsPerRelay = 12,
    int maxConcurrentPublishes = 10,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final publishes = RelayPublishes(relayManager: relayManager);
    return PublishQueue._(
      publishFn: (event, relays, {account}) => publishes
          .publish(
            event,
            relays: relays,
            auth: authPolicyOf?.call(event, account),
            timeout: publishTimeout,
          )
          .done,
      relayListFn: relayListFn,
      store: store,
      tickInterval: tickInterval,
      initialBackoff: initialBackoff,
      maxBackoff: maxBackoff,
      maxInaccessibleAttemptsPerRelay: maxInaccessibleAttemptsPerRelay,
      maxConcurrentPublishes: maxConcurrentPublishes,
      onlineSignal:
          onlineSignal ??
          publicRelayReachability(relayManager.relayConnectivityChanges),
      pauseWhileOffline: onlineSignal != null,
      onError: onError,
    );
  }

  /// Persists [event] for delivery, then fires the first attempt in the
  /// background. The returned [QueuedPublish] reflects the persisted state,
  /// not the attempt outcome. [event] must be signed: the queue never signs.
  ///
  /// A [relaySet] that needs a lookup is stored unresolved and resolved by the
  /// worker, so this call never waits on the network. One that needs no lookup
  /// is resolved here and must yield at least one ws or wss relay url; the
  /// others are dropped. A Blossom leaf throws [ArgumentError]: it names
  /// servers, not relays.
  ///
  /// [account] is the pubkey of the local account the entry is queued under,
  /// so it can later be dropped by [clearLocalAccountData], and is handed to
  /// the [PublishFn]. It need not be `event.pubkey`: for a gift wrap (kind
  /// 1059) it is the real sender, not the event's ephemeral key. Leave it
  /// `null` and the entry is unattributed: retried like any other, but never
  /// removed by an account-scoped clear.
  ///
  /// Records are keyed by `(event.id, account)`. If one with the same pair
  /// already exists, the new relays are merged into it and it is rescheduled
  /// for an immediate attempt, its backoff reset: explicit relays join its
  /// relay list, a set that needs a lookup is resolved and its relays joined.
  /// The event payload is *not* overwritten; the original event wins. A
  /// record stopped by [cancel] is reopened. The same event queued under a
  /// different [account] is a separate record.
  ///
  /// For a replaceable or addressable [event], relays only keep the latest
  /// version. So a pending record of an older version waits while newer
  /// versions, whatever their [account], are headed to every relay it owes,
  /// and becomes [QueuedPublishStatus.superseded] once they hold them all. It
  /// goes out if a newer version does not reach one of them. This holds for a
  /// version older than one already in the store too, and [publish] reopens a
  /// superseded record.
  Future<QueuedPublish> publish(
    Nip01Event event, {
    required UrlSet relaySet,
    String? account,
  }) async {
    _ensureNotDisposed();
    if (event.sig == null) {
      throw ArgumentError.value(event.id, 'event', 'must be signed');
    }
    if (relaySet.kinds.contains(UrlListKind.blossom)) {
      throw ArgumentError.value(
        relaySet,
        'relaySet',
        'reads Blossom server lists',
      );
    }
    if (relaySet.needsLookup && _relayListFn == null) {
      throw StateError('this relaySet needs a relayListFn to resolve');
    }
    final now = _now();
    final key = QueuedPublish.keyFor(eventId: event.id, account: account);

    final stored = await _store.put(key, (existing) async {
      if (relaySet.needsLookup) {
        final pending = existing?.pendingRelaySet;
        return existing?.copyWith(
              pendingRelaySet: pending == null
                  ? relaySet
                  : UrlSet.union([pending, relaySet]),
              resolutionAttempts: 0,
              clearResolutionError: true,
              onlineFailures: 0,
              nextAttemptAt: now,
              clearSuperseded: true,
              clearCancelled: true,
            ) ??
            _newRecord(
              event,
              account,
              now,
              relays: const [],
              pendingRelaySet: relaySet,
            );
      }
      final resolved = await resolveUrlSet(relaySet, _noLookup) as UrlsResolved;
      final relays = _relayUrls(resolved.urls);
      if (relays.isEmpty) {
        throw ArgumentError.value(relaySet, 'relaySet', 'has no relay');
      }
      if (existing == null) {
        return _newRecord(event, account, now, relays: relays);
      }
      final mergedRelays = _relayUrls([...existing.relays, ...relays]);
      // Terminal timestamps are monotonic facts, but adding a relay that is
      // not already covered by that terminal state reopens the entry.
      final fullyAcked = mergedRelays.every(existing.ackedRelays.contains);
      final fullySettled = mergedRelays.every(
        (relay) =>
            existing.ackedRelays.contains(relay) ||
            existing.terminalErrors.containsKey(relay),
      );
      return existing.copyWith(
        relays: mergedRelays,
        onlineFailures: 0,
        nextAttemptAt: now,
        clearDelivered: !fullyAcked,
        clearFailed: !fullyAcked && !fullySettled,
        clearSuperseded: true,
        clearCancelled: true,
      );
    });
    _request(stored.key);
    return stored;
  }

  QueuedPublish _newRecord(
    Nip01Event event,
    String? account,
    int now, {
    required List<RelayUrl> relays,
    UrlSet? pendingRelaySet,
  }) => QueuedPublish(
    id: event.id,
    account: account,
    event: event,
    relays: relays,
    pendingRelaySet: pendingRelaySet,
    ackedRelays: const [],
    lastErrors: const {},
    terminalErrors: const {},
    inaccessibleAttempts: const {},
    attempts: 0,
    firstAttemptAt: null,
    lastAttemptAt: null,
    nextAttemptAt: now,
    deliveredAt: null,
    failedAt: null,
    createdAt: now,
  );

  static Future<UrlListLookup> _noLookup(String _, UrlListKind _) =>
      throw StateError('explicit relay sets never look up a relay list');

  /// Re-pushes a queued event without rewriting its delivery history.
  ///
  /// `ackedRelays` is monotonic and append-only over an entry's lifetime:
  /// a relay that has confirmed receipt stays confirmed forever. `republish`
  /// never clears acks; it sets a one-shot `forcedRelays` override that the
  /// next attempt consumes.
  ///
  /// - `relay == null`: schedules an immediate attempt that pushes to every
  ///   relay in the entry's `relays` list, including those already acked.
  ///   `deliveredAt` is preserved.
  /// - `relay != null`: adds [relay] to the entry's `relays` list if absent,
  ///   schedules an immediate one-shot push to that single relay. If the
  ///   relay is new, `deliveredAt` is cleared (the entry can no longer claim
  ///   100% delivery until the new relay acks) and the backoff is reset;
  ///   otherwise both are preserved. Throws an [ArgumentError] when it is not
  ///   a ws or wss url.
  ///
  /// A superseded or cancelled record still gets this one push, but keeps its
  /// status.
  ///
  /// [account] selects which record to republish, matching the value passed
  /// to [publish]. Returns `null` if no such record exists.
  Future<QueuedPublish?> republish(
    String eventId, {
    String? account,
    String? relay,
  }) async {
    _ensureNotDisposed();
    final RelayUrl? relayUrl;
    if (relay == null) {
      relayUrl = null;
    } else {
      relayUrl =
          RelayUrl.tryParse(relay) ??
          (throw ArgumentError.value(relay, 'relay', 'is not a relay url'));
    }
    final now = _now();
    final key = QueuedPublish.keyFor(eventId: eventId, account: account);
    final updated = await _store.update(key, (current) {
      if (relayUrl == null) {
        return current.copyWith(
          forcedRelays: List<RelayUrl>.from(current.relays),
          nextAttemptAt: now,
        );
      }
      final isNew = !current.relays.contains(relayUrl);
      final relays = isNew ? [...current.relays, relayUrl] : current.relays;
      return current.copyWith(
        relays: relays,
        forcedRelays: [relayUrl],
        onlineFailures: isNew ? 0 : null,
        nextAttemptAt: now,
        clearDelivered: isNew,
        clearFailed: isNew,
      );
    });
    if (updated != null) _request(key);
    return updated;
  }

  /// Stops the retries of a pending record: it becomes
  /// [QueuedPublishStatus.cancelled], leaves [watchPending] and stays in
  /// [listAll].
  /// Its unresolved relay set and any push queued by [republish] are dropped.
  /// A delivered, failed or superseded record keeps its status and only loses
  /// a queued [republish] push.
  ///
  /// An attempt already in flight still completes and records its acks. Relays
  /// that acked keep the event; cancelling does not delete it from them.
  /// Calling [publish] again for the same record reopens it.
  ///
  /// [account] selects which record to cancel, matching the value passed to
  /// [publish]. Returns `null` if no such record exists.
  Future<QueuedPublish?> cancel(String eventId, {String? account}) async {
    _ensureNotDisposed();
    final key = QueuedPublish.keyFor(eventId: eventId, account: account);
    return _store.update(key, (current) {
      if (current.status == QueuedPublishStatus.pending) {
        return current.copyWith(
          cancelledAt: _now(),
          clearPendingRelaySet: true,
          clearForcedRelays: true,
        );
      }
      if (current.forcedRelays == null) return null;
      return current.copyWith(clearForcedRelays: true);
    });
  }

  /// Triggers an immediate scan for due entries. Safe to call repeatedly;
  /// in-flight attempts are not duplicated.
  Future<void> retryNow() async {
    _ensureNotDisposed();
    await _tick();
  }

  /// Returns the currently persisted record for `(eventId, account)`, or
  /// `null` if none exists.
  Future<QueuedPublish?> get(String eventId, {String? account}) =>
      _store.get(QueuedPublish.keyFor(eventId: eventId, account: account));

  /// Live snapshot of the record for `(eventId, account)`. Emits `null`
  /// if/while the record is absent.
  Stream<QueuedPublish?> watch(String eventId, {String? account}) =>
      _store.watch(QueuedPublish.keyFor(eventId: eventId, account: account));

  /// Live snapshot of every record that still has retryable relays, across all
  /// accounts, in the order they were queued. Filter on
  /// [QueuedPublish.account] for a single account.
  Stream<List<QueuedPublish>> watchPending() => _store.watchPending();

  /// One-shot read of every record in the store, delivered or not, across all
  /// accounts, in the order they were queued.
  Future<List<QueuedPublish>> listAll() => _store.findAll();

  /// Removes the record for `(eventId, account)`, settled or not, and returns
  /// it, or `null` if none exists. A pending record is dropped for good. An
  /// attempt in flight still completes, but records nothing.
  Future<QueuedPublish?> remove(String eventId, {String? account}) async {
    _ensureNotDisposed();
    return _store.delete(
      QueuedPublish.keyFor(eventId: eventId, account: account),
    );
  }

  /// Removes the settled records queued before [queuedBefore], across all
  /// accounts: those delivered, failed, superseded or cancelled, unless a
  /// [republish] push is still queued. Pending records stay.
  Future<void> removeSettled({required DateTime queuedBefore}) async {
    _ensureNotDisposed();
    await _store.deleteSettled(
      createdBefore: queuedBefore.millisecondsSinceEpoch,
    );
  }

  /// Removes every entry queued under [account], delivered or
  /// not. Pending entries are dropped for good and will never be retried.
  /// Entries queued without an account (see [publish]) are left untouched;
  /// use [clearAllLocalData] to remove those.
  ///
  /// Safe to call while attempts are in flight: the write of a concurrent
  /// attempt no-ops once the record is gone, so it cannot resurrect a cleared
  /// entry. Calls take effect in the order they are made: a [publish] called
  /// before the clear is cleared with it.
  Future<void> clearLocalAccountData({required String account}) async {
    await _store.deleteByAccount(account);
  }

  /// Removes every entry, all accounts and unattributed entries
  /// included.
  Future<void> clearAllLocalData() async {
    await _store.deleteAll();
  }

  /// Starts the periodic retry timer and replays anything already due.
  /// Also subscribes to the online signal. Idempotent: calling it more than
  /// once is a no-op.
  void start() {
    _ensureNotDisposed();
    if (_tickTimer != null) return;
    _tickTimer = Timer.periodic(_tickInterval, (_) => _periodicTick());
    if (_onlineSignal != null && _onlineSub == null) {
      _onlineSub = _onlineSignal.listen(_handleOnlineChange);
    }
    // Until the signal emits, the queue behaves as if it had none.
    _periodicTick();
  }

  /// Stops the retry timer and the online signal subscription, then waits for
  /// the writes to the store, so the caller can safely close the database
  /// behind it. An attempt still waiting on the network, or a relay set
  /// resolution waiting on a signer, is abandoned without writing.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _disposal.complete();
    _tickTimer?.cancel();
    _tickTimer = null;
    await _onlineSub?.cancel();
    _onlineSub = null;
    await Future.wait(_scans.toList());
    await Future.wait(_inFlight.values.toList());
    await _store.idle;
  }

  void _handleOnlineChange(bool online) {
    if (_disposed) return;
    final wasOffline = _isOnline == false;
    _isOnline = online;
    if (wasOffline && online) {
      _unreachable.clear();
      _background(_tick());
    }
  }

  void _periodicTick() {
    if (_disposed) return;
    if (_pauseWhileOffline && _isOnline == false) return;
    _background(_tick());
  }

  Future<void> _tick() {
    if (_disposed) return Future.value();
    final scan = _attemptDue();
    _scans.add(scan);
    return scan.whenComplete(() => _scans.remove(scan));
  }

  Future<void> _attemptDue() async {
    final due = await _store.findDue(now: _now());
    for (final record in due) {
      if (_disposed) return;
      _background(_attempt(record.key));
    }
  }

  /// Attempts the record at [key] now, or once the attempt in flight for it
  /// is done.
  void _request(String key) {
    if (_inFlight.containsKey(key)) {
      _requested.add(key);
    } else {
      _background(_attempt(key));
    }
  }

  void _background(Future<void> work) =>
      unawaited(work.then((_) {}, onError: _onError));

  /// [future], or null once the queue is disposed.
  Future<T?> _untilDisposed<T extends Object>(Future<T> future) =>
      Future.any([future, _disposal.future.then((_) => null)]);

  Future<void> _attempt(String key) async {
    if (_disposed) return;
    if (_inFlight.containsKey(key)) return;
    final completer = Completer<void>();
    _inFlight[key] = completer.future;

    try {
      var record = await _store.get(key);
      if (record == null || await _leftToNewerVersions(record)) return;
      if (record.pendingRelaySet != null) {
        record = await _resolvePendingRelaySet(record);
        if (record == null || await _leftToNewerVersions(record)) return;
      }
      final release = await _untilDisposed(_publishSlots.acquire());
      if (release == null) return;
      try {
        await _push(key);
      } finally {
        release();
      }
    } finally {
      _inFlight.remove(key);
      completer.complete();
      if (_requested.remove(key)) _request(key);
    }
  }

  /// Whether [record] is left to the newer versions of its event instead of
  /// being sent: they are headed to every relay it owes, or hold them all and
  /// it is superseded.
  Future<bool> _leftToNewerVersions(QueuedPublish record) async {
    switch (_store.coverage(record)) {
      case Coverage.none:
        return false;
      case Coverage.headedTo:
        return true;
      case Coverage.held:
        await _store.supersede(record.key);
        return true;
    }
  }

  /// Pushes the record at [key] to the relays it is owed, then records what
  /// each relay did.
  Future<void> _push(String key) async {
    final record = await _store.get(key);
    if (record == null) return;
    // A terminal entry only re-enters _attempt if a force-push is queued.
    if (record.status != QueuedPublishStatus.pending &&
        record.forcedRelays == null) {
      return;
    }

    final forced = record.forcedRelays;
    final targets = forced ?? record.remainingRelays;
    if (targets.isEmpty) {
      // Nothing to push. Sync terminal timestamps if we somehow got here
      // with stale nulls.
      await _store.update(key, (current) {
        final terminal = _terminalState(
          current.relays,
          current.ackedRelays,
          current.terminalErrors.keys,
        );
        final setDelivered =
            terminal == _AttemptTerminalState.delivered &&
            current.deliveredAt == null;
        final setFailed =
            terminal == _AttemptTerminalState.failed &&
            current.failedAt == null;
        final consumed =
            current.forcedRelays != null &&
            identical(current.forcedRelays, forced);
        if (!setDelivered && !setFailed && !consumed) return null;
        return current.copyWith(
          deliveredAt: setDelivered ? _now() : null,
          failedAt: setFailed ? _now() : null,
          clearFailed: setDelivered,
          clearForcedRelays: consumed,
        );
      });
      return;
    }

    final attemptStart = _now();
    final waiting = <RelayUrl, UnreachableRelay>{
      if (forced == null)
        for (final relay in targets)
          relay: ?_unreachable.waiting(relay, attemptStart),
    };
    final sent = [
      for (final relay in targets)
        if (!waiting.containsKey(relay)) relay,
    ];
    final startedOnline = _isOnline;
    var outcomes = const <RelayUrl, RelayPublishOutcome>{};
    String? publishError;
    if (sent.isNotEmpty) {
      try {
        final result = await _untilDisposed(
          _publishFn(record.event, sent, account: record.account),
        );
        if (result == null) return;
        outcomes = {
          for (final MapEntry(:key, :value) in result.entries)
            ?RelayUrl.tryParse(key): value,
        };
      } catch (e) {
        if (_disposed) return;
        publishError = e.toString();
      }
    }
    final answeredAt = _now();
    if (sent.any((relay) => _answered(outcomes[relay]))) {
      _lastAnswerAt = answeredAt;
    }
    final online =
        (_lastAnswerAt ?? -1) >= attemptStart ||
        (startedOnline == true && _isOnline == true);
    final offline = !online && (startedOnline == false || _isOnline == false);
    final unreachableAttempts = <RelayUrl, int>{};
    for (final relay in sent) {
      final outcome = outcomes[relay];
      if (_answered(outcome)) {
        _unreachable.answered(relay);
      } else if (online && _isInaccessible(outcome, publishError)) {
        unreachableAttempts[relay] = _unreachable.failed(
          relay,
          _retryableError(outcome, publishError),
          answeredAt,
          _backoff,
        );
      }
    }

    await _store.update(key, (current) {
      final newAcked = Set<RelayUrl>.from(current.ackedRelays);
      final newErrors = Map<RelayUrl, String>.from(current.lastErrors);
      final newTerminalErrors = Map<RelayUrl, String>.from(
        current.terminalErrors,
      );
      final newInaccessibleAttempts = Map<RelayUrl, int>.from(
        current.inaccessibleAttempts,
      );

      void unreachable(RelayUrl relay, int count, String error) {
        newInaccessibleAttempts[relay] = count;
        if (count >= _maxInaccessibleAttemptsPerRelay) {
          newTerminalErrors[relay] = 'max-inaccessible-attempts: $error';
          newErrors.remove(relay);
        } else {
          newErrors[relay] = error;
        }
      }

      for (final relay in sent) {
        final outcome = outcomes[relay];
        final alreadyAcked = current.ackedRelays.contains(relay);
        final alreadyTerminal = current.terminalErrors.containsKey(relay);
        if (outcome != null && outcome.accepted) {
          newAcked.add(relay);
          newErrors.remove(relay);
          newTerminalErrors.remove(relay);
          newInaccessibleAttempts.remove(relay);
        } else if (_terminalError(outcome) case final error?) {
          if (!alreadyAcked) {
            newTerminalErrors[relay] = error;
            newErrors.remove(relay);
            newInaccessibleAttempts.remove(relay);
          }
        } else if (!alreadyAcked && !alreadyTerminal) {
          // Acks are monotonic: a transient failure does not invalidate
          // historical confirmation. We only surface errors for relays
          // that have never confirmed or terminally failed.
          final error = _retryableError(outcome, publishError);
          if (_answered(outcome)) {
            newInaccessibleAttempts.remove(relay);
            newErrors[relay] = error;
          } else if (unreachableAttempts[relay] case final attempts?) {
            final count = (newInaccessibleAttempts[relay] ?? 0) + 1;
            unreachable(relay, max(count, attempts), error);
          } else {
            newErrors[relay] = error;
          }
        }
      }
      for (final MapEntry(key: relay, value: skipped) in waiting.entries) {
        if (current.ackedRelays.contains(relay) ||
            current.terminalErrors.containsKey(relay)) {
          continue;
        }
        final count = newInaccessibleAttempts[relay] ?? 0;
        unreachable(relay, max(count, skipped.failures), skipped.error);
      }
      for (final ok in newAcked) {
        newErrors.remove(ok);
        newTerminalErrors.remove(ok);
        newInaccessibleAttempts.remove(ok);
      }
      for (final terminal in newTerminalErrors.keys) {
        newErrors.remove(terminal);
      }

      final terminalState = _terminalState(
        current.relays,
        newAcked,
        newTerminalErrors.keys,
      );
      final delivered = terminalState == _AttemptTerminalState.delivered;
      final failed = terminalState == _AttemptTerminalState.failed;
      final tried = sent.isNotEmpty;
      final onlineFailures = tried && !offline && !delivered && !failed
          ? current.onlineFailures + 1
          : current.onlineFailures;
      final int nextAttemptAt;
      if (delivered || failed) {
        nextAttemptAt = attemptStart;
      } else if (!tried) {
        nextAttemptAt = waiting.values.map((w) => w.retryAt).reduce(min);
      } else {
        final delay = offline ? _initialBackoff : _backoff(onlineFailures);
        nextAttemptAt = _now() + delay.inMilliseconds;
      }

      return current.copyWith(
        ackedRelays: newAcked.toList(growable: false),
        lastErrors: newErrors,
        terminalErrors: newTerminalErrors,
        inaccessibleAttempts: newInaccessibleAttempts,
        attempts: tried ? current.attempts + 1 : null,
        onlineFailures: onlineFailures,
        firstAttemptAt: tried ? (current.firstAttemptAt ?? attemptStart) : null,
        lastAttemptAt: tried ? attemptStart : null,
        nextAttemptAt: nextAttemptAt,
        // deliveredAt is monotonic: once set it stays set (the historical
        // 100% confirmation is preserved). Only set it the first time.
        deliveredAt: delivered
            ? (current.deliveredAt ?? _now())
            : current.deliveredAt,
        failedAt: failed ? (current.failedAt ?? _now()) : current.failedAt,
        clearFailed: delivered || !failed,
        clearForcedRelays: identical(current.forcedRelays, forced),
      );
    });
  }

  Duration _backoff(int attempts) => computeBackoff(
    attempts: attempts,
    initial: _initialBackoff,
    max: _maxBackoff,
    random: _random,
  );

  /// Resolves [record]'s pending relay set and freezes the result. Returns the
  /// resolved record, or `null` when the set stays pending: a lookup was
  /// unavailable, or `publish` changed the set meanwhile.
  Future<QueuedPublish?> _resolvePendingRelaySet(QueuedPublish record) async {
    final set = record.pendingRelaySet!;
    final resolution = await _untilDisposed(_resolve(set));
    if (resolution == null) return null;

    final now = _now();
    final updated = await _store.update(record.key, (current) {
      if (current.pendingRelaySet != set) return null;
      if (resolution.unavailable case final reason?) {
        final attempts = current.resolutionAttempts + 1;
        final delay = _backoff(attempts);
        return current.copyWith(
          resolutionAttempts: attempts,
          resolutionError: reason,
          nextAttemptAt: now + delay.inMilliseconds,
        );
      }
      final merged = _relayUrls([...current.relays, ...resolution.urls]);
      final terminal = _terminalState(
        merged,
        current.ackedRelays,
        current.terminalErrors.keys,
      );
      final delivered = terminal == _AttemptTerminalState.delivered;
      final failed = terminal == _AttemptTerminalState.failed;
      return current.copyWith(
        relays: merged,
        clearPendingRelaySet: true,
        resolutionAttempts: 0,
        resolutionError: merged.isEmpty
            ? 'relay set resolved to no relay'
            : null,
        clearResolutionError: merged.isNotEmpty,
        nextAttemptAt: now,
        deliveredAt: delivered ? (current.deliveredAt ?? now) : null,
        clearDelivered: !delivered,
        failedAt: failed ? (current.failedAt ?? now) : null,
        clearFailed: !failed,
      );
    });
    if (updated == null || updated.pendingRelaySet != null) return null;
    return updated;
  }

  /// The urls [set] resolves to, or why a list it depends on is unavailable.
  Future<({List<String> urls, String? unavailable})> _resolve(
    UrlSet set,
  ) async {
    final relayListFn = _relayListFn;
    if (relayListFn == null) {
      return (urls: const <String>[], unavailable: 'no relayListFn configured');
    }
    try {
      return switch (await resolveUrlSet(set, relayListFn)) {
        UrlsResolved(:final urls) => (urls: urls, unavailable: null),
        UrlsUnavailable(:final reason) => (
          urls: const <String>[],
          unavailable: reason,
        ),
      };
    } catch (e) {
      return (urls: const <String>[], unavailable: e.toString());
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('the PublishQueue was disposed');
    }
  }

  /// [urls] normalized and deduplicated, without those that are not ws or wss
  /// urls.
  static List<RelayUrl> _relayUrls(Iterable<String> urls) =>
      {for (final url in urls) ?RelayUrl.tryParse(url)}.toList(growable: false);

  static bool _answered(RelayPublishOutcome? outcome) =>
      switch (outcome?.status) {
        RelayPublishStatus.accepted || RelayPublishStatus.refused => true,
        _ => false,
      };

  /// Why [outcome] refuses the event for good, or null when retrying may help.
  static String? _terminalError(RelayPublishOutcome? outcome) =>
      switch (outcome) {
        RelayPublishOutcome(
          status: RelayPublishStatus.refused,
          :final message,
        ) =>
          _hasTerminalPrefix(message) ? message : null,
        RelayPublishOutcome(:final failure?)
            when _terminalFailures.contains(failure.kind) =>
          '$failure',
        _ => null,
      };

  static bool _hasTerminalPrefix(String message) {
    final prefixEnd = message.indexOf(':');
    if (prefixEnd <= 0) return false;
    final prefix = message.substring(0, prefixEnd).trim().toLowerCase();
    return _terminalOkFalsePrefixes.contains(prefix);
  }

  static String _retryableError(
    RelayPublishOutcome? outcome,
    String? publishError,
  ) => switch (outcome) {
    null || RelayPublishOutcome(status: RelayPublishStatus.pending) =>
      publishError ?? 'no response',
    RelayPublishOutcome(status: RelayPublishStatus.timedOut) => 'timed out',
    RelayPublishOutcome(status: RelayPublishStatus.failed, :final failure) =>
      '${failure ?? 'failed'}',
    RelayPublishOutcome(:final message) =>
      message.isEmpty ? 'refused' : message,
  };

  /// Whether [outcome] says the relay could not be reached, as opposed to a
  /// relay that answered or an identity it could not use.
  static bool _isInaccessible(
    RelayPublishOutcome? outcome,
    String? publishError,
  ) => switch (outcome) {
    null => publishError == null,
    RelayPublishOutcome(
      status: RelayPublishStatus.pending || RelayPublishStatus.timedOut,
    ) =>
      true,
    RelayPublishOutcome(status: RelayPublishStatus.failed, :final failure) =>
      _unreachableFailures.contains(failure?.kind),
    _ => false,
  };

  _AttemptTerminalState _terminalState(
    List<RelayUrl> relays,
    Iterable<RelayUrl> ackedRelays,
    Iterable<RelayUrl> terminalRelays,
  ) {
    if (relays.isEmpty) return _AttemptTerminalState.failed;
    final acked = ackedRelays.toSet();
    final terminal = terminalRelays.toSet();
    final hasTerminal = relays.any(terminal.contains);
    final allAcked = relays.every(acked.contains);
    if (allAcked) return _AttemptTerminalState.delivered;
    final allSettled = relays.every(
      (relay) => acked.contains(relay) || terminal.contains(relay),
    );
    if (allSettled && hasTerminal) return _AttemptTerminalState.failed;
    return _AttemptTerminalState.pending;
  }
}

const _terminalOkFalsePrefixes = <String>{
  'blocked',
  'invalid',
  'mute',
  'pow',
  'restricted',
};

const _terminalFailures = <RelayFailureKind>{
  RelayFailureKind.blocked,
  RelayFailureKind.messageTooLong,
};

const _unreachableFailures = <RelayFailureKind>{
  RelayFailureKind.unreachable,
  RelayFailureKind.connectionLost,
  RelayFailureKind.connectionFull,
  RelayFailureKind.requestEnded,
};

enum _AttemptTerminalState { pending, failed, delivered }
