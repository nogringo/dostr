import 'dart:async';
import 'dart:math';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:sembast/sembast.dart' show Database;

import 'backoff.dart';
import 'publish_slots.dart';
import 'queue_store.dart';
import 'queued_broadcast.dart';
import 'relay_reachability.dart';

/// Sends [event] to [relays] once and gives what each relay did with it, as
/// `RelayPublishes.publish` of dostr_core does. [account] is the account the
/// event was queued under, see [BroadcastQueue.broadcast].
///
/// It must complete: `RelayPublishes.publish` does once its timeout runs out.
/// A relay missing from the result counts as one that did not answer.
typedef BroadcastFn =
    Future<Map<RelayUrl, RelayPublishOutcome>> Function(
      Nip01Event event,
      List<RelayUrl> relays, {
      String? account,
    });

/// An offline-first queue of events to publish.
///
/// Contract:
///  - `broadcast(event, relaySet: ...)` persists the event before returning,
///    without touching the network.
///  - A [UrlSet] is resolved by the worker, once, then frozen into the
///    record's relays.
///  - Delivery is guaranteed in the eventual sense: the queue keeps retrying
///    each `pending` entry until every relay has accepted it or refused it for
///    good.
///  - Records are never auto-deleted. A terminal entry stays in the store for
///    manual `rebroadcast` or inspection. Explicit removal is available via
///    `clearLocalAccountData` and `clearAllLocalData`.
class BroadcastQueue {
  final BroadcastFn _broadcastFn;
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

  Timer? _tickTimer;
  StreamSubscription<bool>? _onlineSub;
  bool _isOnline = true;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Set<Future<void>> _scans = {};
  bool _disposed = false;
  final Completer<void> _disposal = Completer<void>();

  BroadcastQueue._({
    required BroadcastFn broadcastFn,
    required UrlListFn? relayListFn,
    required Database db,
    required String storeName,
    required Duration tickInterval,
    required Duration initialBackoff,
    required Duration maxBackoff,
    required int maxInaccessibleAttemptsPerRelay,
    required int maxConcurrentPublishes,
    required Stream<bool>? onlineSignal,
    required bool pauseWhileOffline,
    Random? random,
    int Function()? now,
  }) : _broadcastFn = broadcastFn,
       _relayListFn = relayListFn,
       _store = QueueStore(db: db, storeName: storeName),
       _tickInterval = tickInterval,
       _initialBackoff = initialBackoff,
       _maxBackoff = maxBackoff,
       _maxInaccessibleAttemptsPerRelay = maxInaccessibleAttemptsPerRelay,
       _onlineSignal = onlineSignal,
       _pauseWhileOffline = pauseWhileOffline,
       _publishSlots = PublishSlots(maxConcurrentPublishes),
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

  /// A queue that sends with [broadcastFn], for tests or for callers who
  /// publish their own way.
  ///
  /// Pass [onlineSignal] to make the periodic retry loop connectivity-aware:
  /// while the latest emission is `false`, periodic ticks are no-ops, and the
  /// `false -> true` edge triggers an immediate retry pass. `retryNow()`
  /// always runs regardless of this signal. If [onlineSignal] is null the
  /// queue assumes it is always online.
  ///
  /// [maxInaccessibleAttemptsPerRelay] caps consecutive online attempts where
  /// a relay is unreachable for one event. Once reached, that relay is treated
  /// as terminally failed for the event. An attempt counts as online when
  /// [onlineSignal] said so both when it started and when it ended, or when
  /// one of its relays answered. Offline attempts and exceptions thrown by
  /// [broadcastFn] do not increment this counter, and an offline attempt is
  /// retried after [initialBackoff] without growing the backoff.
  ///
  /// [maxConcurrentPublishes] caps the attempts publishing at once. The others
  /// wait their turn, due entries in the order they were queued, so a backlog
  /// piled up offline goes out in order rather than all at once.
  ///
  /// [relayListFn] resolves the relay lists a [UrlSet] refers to, such as
  /// `fetcherUrlListFn` of dostr_fetchers. Without it, only sets that need no
  /// lookup can be broadcast. The queue puts no timeout on it: bound the
  /// network part yourself, and let a signer take as long as it needs.
  BroadcastQueue({
    required BroadcastFn broadcastFn,
    UrlListFn? relayListFn,
    required Database db,
    String storeName = 'broadcasts',
    Duration tickInterval = const Duration(seconds: 30),
    Duration initialBackoff = const Duration(seconds: 5),
    Duration maxBackoff = const Duration(minutes: 30),
    int maxInaccessibleAttemptsPerRelay = 12,
    int maxConcurrentPublishes = 10,
    Stream<bool>? onlineSignal,
    Random? random,
    int Function()? now,
  }) : this._(
         broadcastFn: broadcastFn,
         relayListFn: relayListFn,
         db: db,
         storeName: storeName,
         tickInterval: tickInterval,
         initialBackoff: initialBackoff,
         maxBackoff: maxBackoff,
         maxInaccessibleAttemptsPerRelay: maxInaccessibleAttemptsPerRelay,
         maxConcurrentPublishes: maxConcurrentPublishes,
         onlineSignal: onlineSignal,
         pauseWhileOffline: true,
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
  factory BroadcastQueue.withDostr(
    RelayManager relayManager, {
    required Database db,
    UrlListFn? relayListFn,
    AuthPolicy? Function(Nip01Event event, String? account)? authPolicyOf,
    Duration publishTimeout = defaultPublishTimeout,
    Stream<bool>? onlineSignal,
    String storeName = 'broadcasts',
    Duration tickInterval = const Duration(seconds: 30),
    Duration initialBackoff = const Duration(seconds: 5),
    Duration maxBackoff = const Duration(minutes: 30),
    int maxInaccessibleAttemptsPerRelay = 12,
    int maxConcurrentPublishes = 10,
  }) {
    final publishes = RelayPublishes(relayManager: relayManager);
    return BroadcastQueue._(
      broadcastFn: (event, relays, {account}) => publishes
          .publish(
            event,
            relays: relays,
            auth: authPolicyOf?.call(event, account),
            timeout: publishTimeout,
          )
          .done,
      relayListFn: relayListFn,
      db: db,
      storeName: storeName,
      tickInterval: tickInterval,
      initialBackoff: initialBackoff,
      maxBackoff: maxBackoff,
      maxInaccessibleAttemptsPerRelay: maxInaccessibleAttemptsPerRelay,
      maxConcurrentPublishes: maxConcurrentPublishes,
      onlineSignal:
          onlineSignal ??
          publicRelayReachability(relayManager.relayConnectivityChanges),
      pauseWhileOffline: onlineSignal != null,
    );
  }

  /// Persists [event] for delivery, then fires the first attempt in the
  /// background. The returned [QueuedBroadcast] reflects the persisted state,
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
  /// the [BroadcastFn]. It need not be `event.pubkey`: for a gift wrap (kind
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
  /// version, so a record of an older version that is still pending becomes
  /// [BroadcastStatus.superseded] once newer versions hold, or are headed to,
  /// every relay it owes, whatever their [account]. It is no longer retried.
  /// This holds for a version older than one already in the store too.
  Future<QueuedBroadcast> broadcast(
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
    final key = QueuedBroadcast.keyFor(eventId: event.id, account: account);

    final existing = await _store.get(key);
    final QueuedBroadcast record;
    if (relaySet.needsLookup) {
      final pending = existing?.pendingRelaySet;
      record =
          existing?.copyWith(
            pendingRelaySet: pending == null
                ? relaySet
                : UrlSet.union([pending, relaySet]),
            resolutionAttempts: 0,
            clearResolutionError: true,
            onlineFailures: 0,
            nextAttemptAt: now,
            clearCancelled: true,
          ) ??
          _newRecord(
            event,
            account,
            now,
            relays: const [],
            pendingRelaySet: relaySet,
          );
    } else {
      final resolved = await resolveUrlSet(relaySet, _noLookup) as UrlsResolved;
      final relays = _relayUrls(resolved.urls);
      if (relays.isEmpty) {
        throw ArgumentError.value(relaySet, 'relaySet', 'has no relay');
      }
      if (existing != null) {
        final mergedRelays = _relayUrls([...existing.relays, ...relays]);
        // Terminal timestamps are monotonic facts, but adding a relay that is
        // not already covered by that terminal state reopens the entry.
        final fullyAcked = mergedRelays.every(existing.ackedRelays.contains);
        final fullySettled = mergedRelays.every(
          (relay) =>
              existing.ackedRelays.contains(relay) ||
              existing.terminalErrors.containsKey(relay),
        );
        record = existing.copyWith(
          relays: mergedRelays,
          onlineFailures: 0,
          nextAttemptAt: now,
          clearDelivered: !fullyAcked,
          clearFailed: !fullyAcked && !fullySettled,
          clearCancelled: true,
        );
      } else {
        record = _newRecord(event, account, now, relays: relays);
      }
    }
    final stored = await _store.put(record);

    unawaited(_attempt(record.key));
    return stored;
  }

  QueuedBroadcast _newRecord(
    Nip01Event event,
    String? account,
    int now, {
    required List<RelayUrl> relays,
    UrlSet? pendingRelaySet,
  }) => QueuedBroadcast(
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
  /// a relay that has confirmed receipt stays confirmed forever. `rebroadcast`
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
  /// [account] selects which record to rebroadcast, matching the value passed
  /// to [broadcast]. Returns `null` if no such record exists.
  Future<QueuedBroadcast?> rebroadcast(
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
    final key = QueuedBroadcast.keyFor(eventId: eventId, account: account);
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
    if (updated != null) {
      unawaited(_attempt(key));
    }
    return updated;
  }

  /// Stops the retries of a pending record: it becomes
  /// [BroadcastStatus.cancelled], leaves [watchPending] and stays in [listAll].
  /// Its unresolved relay set and any push queued by [rebroadcast] are dropped.
  /// A delivered, failed or superseded record keeps its status and only loses
  /// a queued [rebroadcast] push.
  ///
  /// An attempt already in flight still completes and records its acks. Relays
  /// that acked keep the event; cancelling does not delete it from them.
  /// Calling [broadcast] again for the same record reopens it.
  ///
  /// [account] selects which record to cancel, matching the value passed to
  /// [broadcast]. Returns `null` if no such record exists.
  Future<QueuedBroadcast?> cancel(String eventId, {String? account}) async {
    _ensureNotDisposed();
    final key = QueuedBroadcast.keyFor(eventId: eventId, account: account);
    return _store.update(key, (current) {
      if (current.status == BroadcastStatus.pending) {
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
  Future<QueuedBroadcast?> get(String eventId, {String? account}) =>
      _store.get(QueuedBroadcast.keyFor(eventId: eventId, account: account));

  /// Live snapshot of the record for `(eventId, account)`. Emits `null`
  /// if/while the record is absent.
  Stream<QueuedBroadcast?> watch(String eventId, {String? account}) =>
      _store.watch(QueuedBroadcast.keyFor(eventId: eventId, account: account));

  /// Live snapshot of every record that still has retryable relays, across all
  /// accounts. Filter on [QueuedBroadcast.account] for a single account.
  Stream<List<QueuedBroadcast>> watchPending() => _store.watchPending();

  /// One-shot read of every record in the store, delivered or not, across all
  /// accounts.
  Future<List<QueuedBroadcast>> listAll() => _store.findAll();

  /// Removes every queued broadcast attributed to [account], delivered or
  /// not. Pending entries are dropped for good and will never be retried.
  /// Entries queued without an account (see [broadcast]) are left untouched;
  /// use [clearAllLocalData] to remove those.
  ///
  /// Safe to call while attempts are in flight: a concurrent attempt writes
  /// through a sembast transaction that no-ops once the record is gone, so it
  /// cannot resurrect a cleared entry. A [broadcast] call for the same account
  /// that overlaps this clear may still re-create its record; do not enqueue
  /// for an account you are clearing.
  Future<void> clearLocalAccountData({required String account}) async {
    await _store.deleteByAccount(account);
  }

  /// Removes every queued broadcast, all accounts and unattributed entries
  /// included. Leaves other sembast stores in the same database untouched.
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
  /// the attempts writing to the store, so the caller can safely close the
  /// sembast database. An attempt still waiting on the network, or a relay
  /// set resolution waiting on a signer, is abandoned without writing.
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
  }

  void _handleOnlineChange(bool online) {
    if (_disposed) return;
    final wasOnline = _isOnline;
    _isOnline = online;
    if (!wasOnline && online) {
      unawaited(_tick());
    }
  }

  void _periodicTick() {
    if (_disposed) return;
    if (_pauseWhileOffline && !_isOnline) return;
    unawaited(_tick());
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
      unawaited(_attempt(record.key));
    }
  }

  /// [future], or null once the queue is disposed.
  Future<T?> _untilDisposed<T extends Object>(Future<T> future) =>
      Future.any([future, _disposal.future.then((_) => null)]);

  Future<void> _attempt(String key) async {
    if (_disposed) return;
    if (_inFlight.containsKey(key)) return;
    final completer = Completer<void>();
    _inFlight[key] = completer.future;

    try {
      final stored = await _store.get(key);
      if (stored == null) return;
      if (stored.pendingRelaySet != null &&
          await _resolvePendingRelaySet(stored) == null) {
        return;
      }
      final release = await _untilDisposed(_publishSlots.acquire());
      if (release == null) return;
      try {
        await _publish(key);
      } finally {
        release();
      }
    } finally {
      _inFlight.remove(key);
      completer.complete();
    }
  }

  /// Pushes the record at [key] to the relays it is owed, then records what
  /// each relay did.
  Future<void> _publish(String key) async {
    final record = await _store.get(key);
    if (record == null) return;
    // A terminal entry only re-enters _attempt if a force-push is queued.
    if (record.status != BroadcastStatus.pending &&
        record.forcedRelays == null) {
      return;
    }

    final targets = record.forcedRelays ?? record.remainingRelays;
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
        if (!setDelivered && !setFailed && current.forcedRelays == null) {
          return null;
        }
        return current.copyWith(
          deliveredAt: setDelivered ? _now() : null,
          failedAt: setFailed ? _now() : null,
          clearFailed: setDelivered,
          clearForcedRelays: true,
        );
      });
      return;
    }

    final attemptStart = _now();
    final startedOnline = _isOnline;
    Map<RelayUrl, RelayPublishOutcome> outcomes;
    String? broadcastError;
    try {
      final sent = await _untilDisposed(
        _broadcastFn(record.event, targets, account: record.account),
      );
      if (sent == null) return;
      outcomes = {
        for (final MapEntry(:key, :value) in sent.entries)
          ?RelayUrl.tryParse(key): value,
      };
    } catch (e) {
      if (_disposed) return;
      broadcastError = e.toString();
      outcomes = const {};
    }
    final answered = targets.any((relay) => _answered(outcomes[relay]));
    final online = (startedOnline && _isOnline) || answered;

    await _store.update(key, (current) {
      final newAcked = Set<RelayUrl>.from(current.ackedRelays);
      final newErrors = Map<RelayUrl, String>.from(current.lastErrors);
      final newTerminalErrors = Map<RelayUrl, String>.from(
        current.terminalErrors,
      );
      final newInaccessibleAttempts = Map<RelayUrl, int>.from(
        current.inaccessibleAttempts,
      );

      for (final relay in targets) {
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
          final error = _retryableError(outcome, broadcastError);
          if (_answered(outcome)) {
            newInaccessibleAttempts.remove(relay);
            newErrors[relay] = error;
          } else if (online && _isInaccessible(outcome, broadcastError)) {
            final count = (newInaccessibleAttempts[relay] ?? 0) + 1;
            newInaccessibleAttempts[relay] = count;
            if (count >= _maxInaccessibleAttemptsPerRelay) {
              newTerminalErrors[relay] = 'max-inaccessible-attempts: $error';
              newErrors.remove(relay);
            } else {
              newErrors[relay] = error;
            }
          } else {
            newErrors[relay] = error;
          }
        }
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
      final onlineFailures = online && !delivered && !failed
          ? current.onlineFailures + 1
          : current.onlineFailures;
      final nextDelay = online
          ? computeBackoff(
              attempts: onlineFailures,
              initial: _initialBackoff,
              max: _maxBackoff,
              random: _random,
            )
          : _initialBackoff;

      return current.copyWith(
        ackedRelays: newAcked.toList(growable: false),
        lastErrors: newErrors,
        terminalErrors: newTerminalErrors,
        inaccessibleAttempts: newInaccessibleAttempts,
        attempts: current.attempts + 1,
        onlineFailures: onlineFailures,
        firstAttemptAt: current.firstAttemptAt ?? attemptStart,
        lastAttemptAt: attemptStart,
        nextAttemptAt: delivered || failed
            ? attemptStart
            : _now() + nextDelay.inMilliseconds,
        // deliveredAt is monotonic: once set it stays set (the historical
        // 100% confirmation is preserved). Only set it the first time.
        deliveredAt: delivered
            ? (current.deliveredAt ?? _now())
            : current.deliveredAt,
        failedAt: failed ? (current.failedAt ?? _now()) : current.failedAt,
        clearFailed: delivered || !failed,
        clearForcedRelays: true,
      );
    });
  }

  /// Resolves [record]'s pending relay set and freezes the result. Returns the
  /// resolved record, or `null` when the set stays pending: a lookup was
  /// unavailable, or `broadcast` changed the set meanwhile.
  Future<QueuedBroadcast?> _resolvePendingRelaySet(
    QueuedBroadcast record,
  ) async {
    final set = record.pendingRelaySet!;
    final resolution = await _untilDisposed(_resolve(set));
    if (resolution == null) return null;

    final now = _now();
    final updated = await _store.update(record.key, (current) {
      if (current.pendingRelaySet != set) return null;
      if (resolution.unavailable case final reason?) {
        final attempts = current.resolutionAttempts + 1;
        final delay = computeBackoff(
          attempts: attempts,
          initial: _initialBackoff,
          max: _maxBackoff,
          random: _random,
        );
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
      throw StateError('the BroadcastQueue was disposed');
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
    String? broadcastError,
  ) => switch (outcome) {
    null || RelayPublishOutcome(status: RelayPublishStatus.pending) =>
      broadcastError ?? 'no response',
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
    String? broadcastError,
  ) => switch (outcome) {
    null => broadcastError == null,
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
