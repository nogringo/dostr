import 'dart:async';
import 'dart:convert';

import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_signer/ndk_signer.dart';
import 'package:ndk_url_set/ndk_url_set.dart';

import 'delivery_policy.dart';
import 'delivery_records.dart';
import 'delivery_response.dart';
import 'delivery_store.dart';
import 'event_delivery_snapshot.dart';

/// Sends [event] to [relayUrl] alone, authenticating as [auth] allows, and
/// completes with what the relay answered. It must not enqueue anything.
typedef DeliverySend =
    Future<List<DeliveryResponse>> Function(
      Nip01Event event,
      String relayUrl,
      AuthPolicy? auth,
    );

/// Background manager for persisted broadcast delivery.
///
/// This usecase persists relay-specific delivery targets, retries due targets,
/// and converges replaceable delivery so only the latest visible version keeps
/// being retried.
///
/// Conceptually:
/// - the broadcaster decides that an event should be sent and enqueues it
/// - [PendingBroadcastDelivery] remembers where it still needs to go and when
///   it should be retried
class PendingBroadcastDelivery {
  static const Duration defaultRetryInterval = Duration(seconds: 15);
  static const Duration defaultSignAttemptTimeout = Duration(seconds: 15);
  final DeliveryStore _store;
  final AuthAccounts _accounts;
  final UrlListFn _urlLists;
  final DeliverySend _send;
  final bool Function(String eventId) _isEventInFlight;
  final Duration _signAttemptTimeout;
  final Set<String> _flushInProgress = {};
  final Map<String, int> _activeSignAttemptIds = {};
  final Map<String, int> _latestSignAttemptIds = {};

  /// auth policy per relay target, keyed by [RelayDeliveryTarget.key] so one
  /// event may go to two relays as two identities. For as long as this process
  /// lives: a signer cannot be persisted, so an account the caller handed over
  /// without ever registering it only survives here. What outlives a restart is
  /// the canonical form on the target, see [_authForTarget].
  final Map<String, AuthPolicy> _authPolicies = {};

  /// the same for an [UnresolvedUrlSet], handed to the targets it resolves to
  final Map<String, AuthPolicy> _unresolvedAuthPolicies = {};
  bool _resolvingUrlSets = false;
  Iterable<String> Function()? _connectedRelayUrlsProvider;
  Timer? _retryTimer;
  StreamSubscription<Iterable<String>>? _openRelayUrlsSubscription;
  final Set<String> _openRelayUrls = {};
  bool _stopped = false;
  final Set<Future<void>> _inFlightOperations = {};

  /// [urlLists] resolves the parts of a broadcast whose lists were unavailable
  /// when it went out. [isEventInFlight] tells whether an event is being sent
  /// right now, so a retry would only duplicate it.
  PendingBroadcastDelivery({
    required DeliveryStore store,
    required AuthAccounts accounts,
    required UrlListFn urlLists,
    required DeliverySend send,
    required bool Function(String eventId) isEventInFlight,
    Duration signAttemptTimeout = defaultSignAttemptTimeout,
  }) : _store = store,
       _accounts = accounts,
       _urlLists = urlLists,
       _send = send,
       _isEventInFlight = isEventInFlight,
       _signAttemptTimeout = signAttemptTimeout;

  /// Starts periodic due-retry processing.
  ///
  /// The callbacks are injected so this class can stay storage-focused and not
  /// depend directly on relay manager internals.
  ///
  /// [openRelayUrlChanges] emits the relays that are open whenever that set
  /// changes. A relay that opens gets its interactive signing retried and its
  /// targets flushed right away, without waiting for the next interval.
  void startPeriodicRetry({
    required Iterable<String> Function() connectedRelayUrls,
    required Future<bool> Function(String relayUrl) reconnectRelay,
    Duration retryInterval = defaultRetryInterval,
    Stream<Iterable<String>>? openRelayUrlChanges,
  }) {
    _stopped = false;
    _connectedRelayUrlsProvider = connectedRelayUrls;
    _openRelayUrlsSubscription?.cancel();
    _openRelayUrls.clear();
    _openRelayUrlsSubscription = openRelayUrlChanges?.listen(_onOpenRelayUrls);
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      retryInterval,
      (_) => _trackOperation(
        retryDueDeliveries(
          connectedRelayUrls: connectedRelayUrls,
          reconnectRelay: reconnectRelay,
        ),
      ),
    );
    _trackOperation(
      retryDueDeliveries(
        connectedRelayUrls: connectedRelayUrls,
        reconnectRelay: reconnectRelay,
      ),
    );
  }

  Future<void> stop() async {
    _stopped = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _openRelayUrlsSubscription?.cancel();
    _openRelayUrlsSubscription = null;
    _openRelayUrls.clear();
    _authPolicies.clear();
    _unresolvedAuthPolicies.clear();
    final operations = _inFlightOperations.toList(growable: false);
    if (operations.isNotEmpty) {
      await Future.wait(operations);
    }
  }

  void _onOpenRelayUrls(Iterable<String> relayUrls) {
    final open = relayUrls.toSet();
    for (final relayUrl in open.difference(_openRelayUrls)) {
      unawaited(retryInteractiveSigningForTransportRelay(relayUrl));
      unawaited(flushForRelay(relayUrl));
    }
    _openRelayUrls
      ..clear()
      ..addAll(open);
  }

  void _trackOperation(Future<void> operation) {
    if (_stopped) {
      return;
    }
    _inFlightOperations.add(operation);
    operation.whenComplete(() {
      _inFlightOperations.remove(operation);
    });
  }

  Future<void> retryDueDeliveries({
    required Iterable<String> Function() connectedRelayUrls,
    required Future<bool> Function(String relayUrl) reconnectRelay,
  }) async {
    if (_stopped) {
      return;
    }
    await _retryDueSigning(reconnectRelay: reconnectRelay);

    if (_stopped) {
      return;
    }
    await _resolveUnresolvedUrlSets();

    if (_stopped) {
      return;
    }

    final connectedRelayUrlSet = connectedRelayUrls().toSet();
    final dueRelayUrlSet = await _relayUrlsWithDuePendingTargets();
    final relayUrls = dueRelayUrlSet.toList()..sort();

    for (final relayUrl in relayUrls) {
      if (_stopped) {
        return;
      }
      if (connectedRelayUrlSet.contains(relayUrl)) {
        await flushForRelay(relayUrl, onlyDue: true);
        continue;
      }

      final connected = await reconnectRelay(relayUrl);
      if (!connected) {
        continue;
      }

      await flushForRelay(relayUrl, onlyDue: true);
    }
  }

  /// Trigger immediate processing of due signing and delivery work.
  ///
  /// Useful as an accelerator when the host app detects network restoration,
  /// foreground resume, or other conditions that may unblock pending signer
  /// approval/completion paths.
  Future<void> retryDueNow({
    required Iterable<String> Function() connectedRelayUrls,
    required Future<bool> Function(String relayUrl) reconnectRelay,
  }) async {
    await retryDueDeliveries(
      connectedRelayUrls: connectedRelayUrls,
      reconnectRelay: reconnectRelay,
    );
  }

  /// Retry unsigned interactive-signing work associated with a signer
  /// transport relay that just became reachable.
  Future<void> retryInteractiveSigningForTransportRelay(String relayUrl) async {
    if (_stopped) {
      return;
    }
    final records = await _store.loadEventDeliveryRecords();
    records.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final record in records) {
      if (_stopped) {
        return;
      }
      if (!record.requiresInteractiveSigning) {
        continue;
      }
      if (record.signingState == EventSigningState.permanentFailure ||
          record.signingState == EventSigningState.needsAction ||
          record.signingState == EventSigningState.signed ||
          record.signedAt != null) {
        continue;
      }

      final event = await _store.loadEvent(record.eventId);
      if (event == null) {
        await _discardEventDelivery(record.eventId);
        continue;
      }

      if (await _discardNonRetryableEvent(event)) {
        continue;
      }

      final signer = _resolveSignerForEvent(event);
      if (signer == null ||
          !signer.requiresSignerNetwork ||
          !signer.signerTransportRelayUrls.contains(relayUrl)) {
        continue;
      }

      await _ensureEventSigned(record, event: event);
    }
  }

  Future<void> enqueueSpecificRelayBroadcast({
    required Nip01Event event,
    required Iterable<String> relayUrls,
    required bool requiresInteractiveSigning,
    AuthPolicy? auth,
  }) async {
    if (_stopped) {
      return;
    }
    // One durable aggregate record plus one durable target per relay gives NDK
    // enough state to recover delivery after restart without mutating a shared
    // in-memory list.
    final relayUrlList = relayUrls.toSet().toList()..sort();
    Logger.log.d(() => 'enqueue pending delivery ${event.id} -> $relayUrlList');
    final existing = await _store.loadEventDeliveryRecord(event.id);
    final now = Nip01Event.secondsSinceEpoch();

    await _store.saveEventDeliveryRecord(
      EventDeliveryRecord(
        eventId: event.id,
        status: existing?.status ?? EventDeliveryStatus.pending,
        signingState:
            existing?.signingState ??
            (requiresInteractiveSigning
                ? EventSigningState.pending
                : EventSigningState.notNeeded),
        createdAt: existing?.createdAt ?? event.createdAt,
        updatedAt: now,
        serializedEventJson:
            _serializeEvent(event) ?? existing?.serializedEventJson,
        signedAt: existing?.signedAt ?? (event.sig != null ? now : null),
        completedAt: existing?.completedAt,
        requiresInteractiveSigning: requiresInteractiveSigning,
        signAttemptCount: existing?.signAttemptCount ?? 0,
        lastSignAttemptAt: existing?.lastSignAttemptAt,
        nextSignRetryAt: existing?.nextSignRetryAt,
        lastSignError: existing?.lastSignError,
      ),
    );

    final existingTargets = await _store.loadRelayDeliveryTargets(
      eventId: event.id,
    );
    final existingByRelay = {
      for (final target in existingTargets) target.relayUrl: target,
    };

    final targets = relayUrlList.map((relayUrl) {
      final existingTarget = existingByRelay[relayUrl];
      if (existingTarget != null) {
        // only the relays of this call are re-attributed; the same event may
        // be on its way to another relay as somebody else
        if (auth == null) {
          return existingTarget;
        }
        final reattributed = existingTarget.copyWith(
          authCanonical: auth.canonical,
        );
        // naming an identity is what a target parked for a missing one was
        // waiting for, so it can move again
        return _isParkedForIdentity(reattributed)
            ? reattributed.copyWith(
                state: RelayDeliveryState.pending,
                lastError: null,
              )
            : reattributed;
      }
      return RelayDeliveryTarget(
        eventId: event.id,
        relayUrl: relayUrl,
        reason: RelayDeliveryReason.explicit,
        authCanonical: auth?.canonical,
      );
    }).toList();

    if (auth != null) {
      // keyed off the targets themselves, so the live policy can only ever be
      // found under the key the persisted target is read back with
      for (final target in targets) {
        _authPolicies[target.key] = auth;
      }
    }

    await _store.saveRelayDeliveryTargets(targets);
  }

  /// Keeps the parts of a broadcast's destinations that were unavailable, so
  /// [retryDueDeliveries] sends to their relays once they resolve. [event] is
  /// signed.
  Future<void> enqueueUnresolvedUrlSets({
    required Nip01Event event,
    required List<UrlSet> urlSets,
    AuthPolicy? auth,
  }) async {
    if (_stopped ||
        DeliveryPolicy.forEvent(event).kind == DeliveryPolicyKind.doNotRetry) {
      return;
    }
    Logger.log.d(() => 'enqueue unresolved delivery ${event.id}');
    final existing = await _store.loadEventDeliveryRecord(event.id);
    final unresolved = {
      for (final set in existing?.unresolvedUrlSets ?? <UnresolvedUrlSet>[])
        set.key: set,
    };
    for (final urlSet in urlSets) {
      final set = UnresolvedUrlSet(
        urlSet: urlSet,
        authCanonical: auth?.canonical,
      );
      unresolved[set.key] = set;
      if (auth != null) {
        _unresolvedAuthPolicies[_unresolvedKey(event.id, set)] = auth;
      }
    }

    final now = Nip01Event.secondsSinceEpoch();
    final serializedEventJson = _serializeEvent(event);
    await _saveSigningOutcome(
      existing?.copyWith(
            updatedAt: now,
            serializedEventJson:
                serializedEventJson ?? existing.serializedEventJson,
            unresolvedUrlSets: unresolved.values.toList(),
          ) ??
          EventDeliveryRecord(
            eventId: event.id,
            createdAt: event.createdAt,
            updatedAt: now,
            serializedEventJson: serializedEventJson,
            signedAt: now,
            unresolvedUrlSets: unresolved.values.toList(),
          ),
    );
  }

  Future<void> persistSpecificRelayBroadcastResult(
    Nip01Event event,
    List<DeliveryResponse> responses,
  ) async {
    if (_stopped) {
      return;
    }
    Logger.log.d(
      () =>
          'persist broadcast result ${event.id} -> ${responses.map((r) => r.relayUrl).toList()}',
    );

    final existing = await _store.loadEventDeliveryRecord(event.id);
    if (existing == null) {
      return;
    }

    final existingTargets = await _store.loadRelayDeliveryTargets(
      eventId: event.id,
    );
    final targetsByRelay = {
      for (final target in existingTargets)
        cleanRelayUrl(target.relayUrl) ?? target.relayUrl: target,
    };

    final updatedTargets = <RelayDeliveryTarget>[];
    final policy = DeliveryPolicy.forEvent(event);
    final attemptTimestamp = Nip01Event.secondsSinceEpoch();
    for (final response in responses) {
      final responseRelayUrl =
          cleanRelayUrl(response.relayUrl) ?? response.relayUrl;
      final current = targetsByRelay[responseRelayUrl];
      if (current == null) {
        continue;
      }

      final nextState = policy.resolveNextState(
        response,
        auth: _authForTarget(current).policy,
      );
      final nextRetryAt = policy.shouldRetryState(nextState)
          ? attemptTimestamp +
                policy
                    .retryDelayFor(
                      state: nextState,
                      attemptCount: current.attemptCount + 1,
                    )
                    .inSeconds
          : null;

      updatedTargets.add(
        current.copyWith(
          state: nextState,
          attemptCount: current.attemptCount + 1,
          lastAttemptAt: attemptTimestamp,
          nextRetryAt: nextRetryAt,
          lastOkMessage: response.accepted
              ? response.message
              : current.lastOkMessage,
          lastError: response.accepted
              ? null
              : response.failure ?? response.message,
        ),
      );
    }

    if (policy.kind == DeliveryPolicyKind.doNotRetry) {
      final updatedRelayUrls = {
        for (final target in updatedTargets) target.relayUrl,
      };
      for (final current in existingTargets) {
        if (updatedRelayUrls.contains(current.relayUrl)) {
          continue;
        }
        if (current.state == RelayDeliveryState.acked ||
            current.state == RelayDeliveryState.permanentFailure) {
          continue;
        }
        updatedTargets.add(
          current.copyWith(
            state: RelayDeliveryState.permanentFailure,
            attemptCount: current.attemptCount + 1,
            lastAttemptAt: attemptTimestamp,
            nextRetryAt: null,
            lastError: 'broadcast completed without relay acknowledgement',
          ),
        );
      }
    }

    if (updatedTargets.isNotEmpty) {
      await _store.saveRelayDeliveryTargets(updatedTargets);
    }

    final allTargets = await _store.loadRelayDeliveryTargets(eventId: event.id);
    final deliveryStatus = _resolveDeliveryStatus(existing, allTargets);
    final completionTimestamp =
        deliveryStatus == EventDeliveryStatus.delivered ||
            deliveryStatus == EventDeliveryStatus.failed
        ? Nip01Event.secondsSinceEpoch()
        : null;

    await _store.saveEventDeliveryRecord(
      existing.copyWith(
        status: deliveryStatus,
        updatedAt: Nip01Event.secondsSinceEpoch(),
        completedAt: completionTimestamp,
      ),
    );
    _dropSettledAuthPolicies(allTargets);
    await _purgeEphemeralIfResolved(
      event.id,
      deliveryStatus,
      event.kind,
      allTargets,
    );
  }

  Future<void> flushForRelay(String relayUrl, {bool onlyDue = false}) async {
    if (_stopped) {
      return;
    }
    // Per-relay flush serialization avoids two concurrent retry paths trying to
    // re-send the same relay targets at once.
    if (!_flushInProgress.add(relayUrl)) {
      return;
    }

    try {
      if (_stopped) {
        return;
      }
      final persistedTargets = await _store.loadRelayDeliveryTargets(
        relayUrl: relayUrl,
        excludeAcked: true,
      );
      final now = Nip01Event.secondsSinceEpoch();
      final targets = persistedTargets.where((target) {
        if (target.state == RelayDeliveryState.permanentFailure) {
          return false;
        }

        if (!onlyDue) {
          return true;
        }

        if (_isParkedForIdentity(target)) {
          return false;
        }

        return target.nextRetryAt == null || target.nextRetryAt! <= now;
      }).toList();
      Logger.log.d(
        () =>
            'flush pending delivery for $relayUrl${onlyDue ? " (due only)" : ""} -> ${targets.map((t) => t.eventId).toList()}',
      );

      for (final target in targets) {
        if (_stopped) {
          return;
        }
        if (_isEventInFlight(target.eventId)) {
          continue;
        }

        final deliveryRecord = await _store.loadEventDeliveryRecord(
          target.eventId,
        );
        if (deliveryRecord == null) {
          await _store.removeRelayDeliveryTarget(
            eventId: target.eventId,
            relayUrl: relayUrl,
          );
          continue;
        }

        final loadedEvent = await _loadRecoverableEvent(
          target.eventId,
          record: deliveryRecord,
        );
        if (loadedEvent == null) {
          await _store.removeRelayDeliveryTarget(
            eventId: target.eventId,
            relayUrl: relayUrl,
          );
          continue;
        }
        var event = loadedEvent;

        if (await _discardNonRetryableEvent(event)) {
          continue;
        }

        if (_isExpiredEvent(event)) {
          Logger.log.d(
            () => 'drop expired pending delivery ${event.id} for $relayUrl',
          );
          await _discardEventDelivery(event.id);
          continue;
        }

        if (await _isObsoleteReplaceableOrAddressableEvent(event)) {
          Logger.log.d(
            () => 'drop obsolete pending delivery ${event.id} for $relayUrl',
          );
          await _discardEventDelivery(event.id);
          continue;
        }

        if (deliveryRecord.requiresInteractiveSigning && event.sig == null) {
          final signed = await _ensureEventSigned(deliveryRecord, event: event);
          if (!signed) {
            continue;
          }
          final signedEvent = await _store.loadEvent(target.eventId);
          if (signedEvent == null || signedEvent.sig == null) {
            continue;
          }
          event = signedEvent;
        }

        final policy = DeliveryPolicy.forEvent(event);
        if (!policy.shouldRetryState(target.state)) {
          continue;
        }

        if (target.state == RelayDeliveryState.attempting &&
            policy.retainsOnlyLatest) {
          Logger.log.d(
            () =>
                'skip retry for in-flight replaceable delivery ${event.id} on $relayUrl',
          );
          continue;
        }

        final auth = _authForTarget(target);
        if (!auth.available) {
          await _parkUnattributableDelivery(target, deliveryRecord);
          continue;
        }

        if (event.sig == null && _accounts.getLoggedAccount() == null) {
          Logger.log.d(
            () => 'skip pending delivery ${event.id} for $relayUrl: no signer',
          );
          continue;
        }

        final List<DeliveryResponse> responses;
        try {
          responses = await _send(event, relayUrl, auth.policy);
        } catch (error, stackTrace) {
          // one failing target must not abort the pass for the others
          Logger.log.w(
            () => 'retry of pending delivery ${event.id} to $relayUrl failed',
            error: error,
            stackTrace: stackTrace,
          );
          continue;
        }
        // Retries bypass Broadcast's initial-send persistence wrapper. Apply
        // the same acknowledgement and backoff bookkeeping before retrying.
        await persistSpecificRelayBroadcastResult(event, responses);
      }
    } finally {
      _flushInProgress.remove(relayUrl);
    }
  }

  /// Returns the joined persisted local-first delivery state for one event id.
  ///
  /// This lets apps inspect events that may still exist only locally after a
  /// restart, including the last persisted per-relay outcome.
  Future<EventDeliverySnapshot?> loadEventDelivery(String eventId) async {
    final record = await _store.loadEventDeliveryRecord(eventId);
    if (record == null) {
      return null;
    }

    return _loadSnapshotForRecord(record);
  }

  /// Lists persisted delivery items.
  ///
  /// By default this returns only events that are not fully delivered yet.
  Future<List<EventDeliverySnapshot>> loadDeliveries({
    bool pendingOnly = true,
    EventDeliveryStatus? status,
    int? limit,
  }) async {
    final records = await _store.loadEventDeliveryRecords(
      status: status,
      limit: limit,
    );
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final snapshots = <EventDeliverySnapshot>[];
    for (final record in records) {
      if (pendingOnly && record.status == EventDeliveryStatus.delivered) {
        continue;
      }
      snapshots.add(await _loadSnapshotForRecord(record));
    }

    return snapshots;
  }

  Future<EventDeliverySnapshot> _loadSnapshotForRecord(
    EventDeliveryRecord record,
  ) async {
    final event = await _store.loadEvent(record.eventId);
    final relayTargets = await _store.loadRelayDeliveryTargets(
      eventId: record.eventId,
    );
    relayTargets.sort((a, b) => a.relayUrl.compareTo(b.relayUrl));

    return EventDeliverySnapshot(
      event: event,
      record: record,
      relayTargets: relayTargets,
    );
  }

  /// The auth policy a retry to this relay must go out under.
  ///
  /// The live policy wins: it holds the [Account] itself, so an identity the
  /// caller handed over without registering it still works. After a restart
  /// only the canonical form is left, and the account behind its pubkey is
  /// looked up in [Accounts], the way [_resolveSignerForEvent] looks up a
  /// signer. An identity nobody can sign for resolves to nothing rather than
  /// falling back to the logged account, which is what the policy ruled out.
  _AuthResolution _authForTarget(RelayDeliveryTarget target) {
    final live = _authPolicies[target.key];
    if (live != null) {
      return _AuthResolution(live);
    }

    final canonical = target.authCanonical;
    if (canonical == null) {
      return const _AuthResolution(null);
    }
    if (canonical == 'never') {
      return const _AuthResolution(AuthPolicy.never());
    }

    final separator = canonical.indexOf(':');
    if (separator < 0) {
      Logger.log.w(() => 'Unknown auth policy "$canonical", ignoring it');
      return const _AuthResolution(null);
    }
    final kind = canonical.substring(0, separator);
    final pubkey = canonical.substring(separator + 1);
    final account = _accounts.accounts[pubkey];
    if (account == null || !account.signer.canSign()) {
      return _AuthResolution.unavailable;
    }

    return switch (kind) {
      'allow' => _AuthResolution(AuthPolicy.allow(account)),
      'require' => _AuthResolution(AuthPolicy.require(account)),
      _ => const _AuthResolution(null),
    };
  }

  /// Holds a delivery whose identity is gone until the app supplies it again,
  /// rather than sending it as somebody else. Re-broadcasting the same event
  /// with [AuthPolicy] in hand rewrites the record and resumes it.
  Future<void> _parkUnattributableDelivery(
    RelayDeliveryTarget target,
    EventDeliveryRecord record,
  ) async {
    Logger.log.w(
      () =>
          'delivery ${target.eventId} to ${target.relayUrl} needs '
          '${target.authCanonical}, which no account can sign for',
    );
    await _store.saveRelayDeliveryTargets([
      target.copyWith(
        state: RelayDeliveryState.authRequired,
        nextRetryAt: null,
        lastError: 'No available account for ${target.authCanonical}',
      ),
    ]);
    await _saveSigningOutcome(record);
  }

  /// A NIP-40 expired event has no delivery value: relays reject it and it will
  /// be swept from cache, so stop retrying and drop the durable delivery state.
  bool _isExpiredEvent(Nip01Event event) {
    final rawValue = event.getFirstTag('expiration');
    if (rawValue == null) {
      return false;
    }
    final expiration = int.tryParse(rawValue);
    if (expiration == null) {
      return false;
    }
    return expiration <= Nip01Event.secondsSinceEpoch();
  }

  Future<bool> _isObsoleteReplaceableOrAddressableEvent(
    Nip01Event event,
  ) async {
    // Replaceable/addressable retries should follow the currently visible cache
    // winner, not historical offline versions that were later superseded.
    final policy = DeliveryPolicy.forEvent(event);
    if (!policy.retainsOnlyLatest) {
      return false;
    }

    final visibleEvents = await _store.loadEvents(
      pubKeys: [event.pubKey],
      kinds: [event.kind],
      tags: _isAddressableKind(event.kind) && event.dTag != null
          ? {
              'd': [event.dTag!],
            }
          : null,
      limit: 1,
    );

    if (visibleEvents.isEmpty) {
      return true;
    }

    return visibleEvents.single.id != event.id;
  }

  /// A live policy is only needed while something may still be sent to that
  /// relay. Dropping the settled ones keeps the map from growing for the life
  /// of the process. A delivery that is revived supplies it again through
  /// [enqueueSpecificRelayBroadcast].
  void _dropSettledAuthPolicies(List<RelayDeliveryTarget> targets) {
    for (final target in targets) {
      if (target.state == RelayDeliveryState.acked ||
          target.state == RelayDeliveryState.permanentFailure) {
        _authPolicies.remove(target.key);
      }
    }
  }

  Future<void> _discardEventDelivery(String eventId) async {
    final prefix = RelayDeliveryTarget.keyPrefixFor(eventId);
    _authPolicies.removeWhere((key, _) => key.startsWith(prefix));
    _unresolvedAuthPolicies.removeWhere((key, _) => key.startsWith(prefix));
    await _store.removeRelayDeliveryTargets(eventId);
    await _store.removeEventDeliveryRecord(eventId);
  }

  /// Ephemeral events may be tracked for their original publication, but
  /// their delivery policy forbids retries. Old pending records must not keep
  /// reconnecting relay or signer transports after that attempt has finished.
  Future<bool> _discardNonRetryableEvent(Nip01Event event) async {
    if (DeliveryPolicy.forEvent(event).kind != DeliveryPolicyKind.doNotRetry) {
      return false;
    }
    if (!_isEventInFlight(event.id)) {
      await _discardEventDelivery(event.id);
    }
    return true;
  }

  /// A target waiting for an identity the app has to name again. Nothing about
  /// it changes on its own, so it must not make its relay due: it would
  /// reconnect and rewrite the same state on every retry interval, forever.
  /// A normal auth-required refusal carries a [RelayDeliveryTarget.nextRetryAt]
  /// and stays retryable.
  bool _isParkedForIdentity(RelayDeliveryTarget target) =>
      target.state == RelayDeliveryState.authRequired &&
      target.nextRetryAt == null;

  static String _unresolvedKey(String eventId, UnresolvedUrlSet set) =>
      '${RelayDeliveryTarget.keyPrefixFor(eventId)}${set.key}';

  /// Turns each unresolved part whose lists can now be looked up into relay
  /// targets, which the rest of the pass then delivers.
  Future<void> _resolveUnresolvedUrlSets() async {
    // a slow lookup must not let the next pass resolve the same parts again
    if (_resolvingUrlSets) {
      return;
    }
    _resolvingUrlSets = true;
    try {
      final records = await _store.loadEventDeliveryRecords();
      await Future.wait([
        for (final record in records)
          if (record.unresolvedUrlSets.isNotEmpty &&
              !_isEventInFlight(record.eventId))
            _resolveUrlSetsOf(record).catchError((
              Object error,
              StackTrace stackTrace,
            ) {
              Logger.log.w(
                () => 'resolving pending delivery ${record.eventId} failed',
                error: error,
                stackTrace: stackTrace,
              );
            }),
      ]);
    } finally {
      _resolvingUrlSets = false;
    }
  }

  Future<void> _resolveUrlSetsOf(EventDeliveryRecord record) async {
    final event = await _loadRecoverableEvent(record.eventId, record: record);
    if (event == null ||
        _isExpiredEvent(event) ||
        await _isObsoleteReplaceableOrAddressableEvent(event)) {
      await _discardEventDelivery(record.eventId);
      return;
    }

    final resolutions = await Future.wait([
      for (final set in record.unresolvedUrlSets)
        resolveUrlSet(set.urlSet, _urlLists),
    ]);
    if (_stopped) {
      return;
    }

    final targets = await _store.loadRelayDeliveryTargets(
      eventId: record.eventId,
    );
    final relayUrls = {for (final target in targets) target.relayUrl};
    final newTargets = <RelayDeliveryTarget>[];
    final resolvedKeys = <String>{};
    for (final (i, resolution) in resolutions.indexed) {
      final set = record.unresolvedUrlSets[i];
      if (resolution is! UrlsResolved) {
        continue;
      }
      resolvedKeys.add(set.key);
      final live = _unresolvedAuthPolicies.remove(
        _unresolvedKey(record.eventId, set),
      );
      for (final relayUrl in cleanRelayUrls(resolution.urls)) {
        // a relay this event already goes to keeps its delivery state
        if (!relayUrls.add(relayUrl)) {
          continue;
        }
        final target = RelayDeliveryTarget(
          eventId: record.eventId,
          relayUrl: relayUrl,
          reason: RelayDeliveryReason.explicit,
          authCanonical: set.authCanonical,
        );
        if (live != null) {
          _authPolicies[target.key] = live;
        }
        newTargets.add(target);
      }
    }
    if (resolvedKeys.isEmpty) {
      return;
    }
    Logger.log.d(
      () =>
          'resolved delivery ${record.eventId} -> ${newTargets.map((t) => t.relayUrl).toList()}',
    );

    // read again, so a part enqueued during the lookups is kept
    final current = await _store.loadEventDeliveryRecord(record.eventId);
    if (current == null) {
      return;
    }
    final stillUnresolved = [
      for (final set in current.unresolvedUrlSets)
        if (!resolvedKeys.contains(set.key)) set,
    ];
    if (relayUrls.isEmpty && stillUnresolved.isEmpty) {
      await _discardEventDelivery(record.eventId);
      return;
    }
    if (newTargets.isNotEmpty) {
      await _store.saveRelayDeliveryTargets(newTargets);
    }
    await _saveSigningOutcome(
      current.copyWith(
        updatedAt: Nip01Event.secondsSinceEpoch(),
        unresolvedUrlSets: stillUnresolved,
      ),
    );
  }

  Future<Set<String>> _relayUrlsWithDuePendingTargets() async {
    final now = Nip01Event.secondsSinceEpoch();
    final targets = await _store.loadRelayDeliveryTargets(excludeAcked: true);

    final relayUrls = <String>{};
    final nonRetryableEventIds = <String>{};
    final checkedEventIds = <String>{};
    for (final target in targets) {
      if (_isEventInFlight(target.eventId)) {
        continue;
      }
      // One event can have many relay targets. Resolve its policy once per
      // pass, before selecting any transport to reconnect.
      if (checkedEventIds.add(target.eventId)) {
        final record = await _store.loadEventDeliveryRecord(target.eventId);
        if (record != null) {
          final event = await _loadRecoverableEvent(
            target.eventId,
            record: record,
          );
          if (event != null && await _discardNonRetryableEvent(event)) {
            nonRetryableEventIds.add(target.eventId);
          }
        }
      }
      if (nonRetryableEventIds.contains(target.eventId)) {
        continue;
      }
      if (target.state == RelayDeliveryState.permanentFailure) {
        continue;
      }
      if (_isParkedForIdentity(target)) {
        continue;
      }
      if (target.nextRetryAt != null && target.nextRetryAt! > now) {
        continue;
      }
      relayUrls.add(target.relayUrl);
    }

    return relayUrls;
  }

  Future<void> _retryDueSigning({
    required Future<bool> Function(String relayUrl) reconnectRelay,
  }) async {
    if (_stopped) {
      return;
    }
    final now = Nip01Event.secondsSinceEpoch();
    final records = await _store.loadEventDeliveryRecords();
    records.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final record in records) {
      if (_stopped) {
        return;
      }
      if (!record.requiresInteractiveSigning) {
        continue;
      }
      if (record.signingState == EventSigningState.permanentFailure ||
          record.signingState == EventSigningState.needsAction) {
        continue;
      }
      if (record.signedAt != null &&
          record.signingState == EventSigningState.signed) {
        continue;
      }
      if (record.nextSignRetryAt != null && record.nextSignRetryAt! > now) {
        continue;
      }

      final event = await _loadRecoverableEvent(record.eventId, record: record);
      if (event == null) {
        await _discardEventDelivery(record.eventId);
        continue;
      }

      if (await _discardNonRetryableEvent(event)) {
        continue;
      }

      if (_isExpiredEvent(event)) {
        await _discardEventDelivery(record.eventId);
        continue;
      }

      if (await _isObsoleteReplaceableOrAddressableEvent(event)) {
        await _discardEventDelivery(record.eventId);
        continue;
      }

      final signer = _resolveSignerForEvent(event);
      if (signer != null &&
          signer.requiresSignerNetwork &&
          !_isSignerTransportReachable(signer)) {
        final signerRelayUrls = signer.signerTransportRelayUrls.toSet().toList()
          ..sort();
        for (final relayUrl in signerRelayUrls) {
          await reconnectRelay(relayUrl);
          if (_isSignerTransportReachable(signer)) {
            break;
          }
        }
      }

      await _ensureEventSigned(record, event: event);
    }
  }

  Future<bool> _ensureEventSigned(
    EventDeliveryRecord record, {
    required Nip01Event event,
  }) async {
    if (_stopped) {
      return false;
    }
    if (!record.requiresInteractiveSigning) {
      return true;
    }
    if (event.sig != null) {
      await _markEventSigned(record);
      return true;
    }

    final signer = _resolveSignerForEvent(event);
    if (signer != null &&
        signer.requiresSignerNetwork &&
        !_isSignerTransportReachable(signer)) {
      return false;
    }

    if (_activeSignAttemptIds.containsKey(event.id)) {
      return false;
    }
    final now = Nip01Event.secondsSinceEpoch();
    final attemptId = (_latestSignAttemptIds[event.id] ?? 0) + 1;
    _latestSignAttemptIds[event.id] = attemptId;
    _activeSignAttemptIds[event.id] = attemptId;
    if (signer == null ||
        !signer.requiresInteractiveSigning ||
        !signer.canSign()) {
      await _saveSigningOutcome(
        record.copyWith(
          signingState: EventSigningState.needsAction,
          updatedAt: now,
          lastSignError:
              'No matching available remote signer account for ${event.pubKey}',
          nextSignRetryAt: null,
        ),
      );
      _activeSignAttemptIds.remove(event.id);
      return false;
    }

    final attemptingRecord = record.copyWith(
      signingState: EventSigningState.attempting,
      updatedAt: now,
      signAttemptCount: record.signAttemptCount + 1,
      lastSignAttemptAt: now,
      lastSignError: null,
    );
    await _saveSigningOutcome(attemptingRecord);

    final signFuture = signer.sign(event);
    try {
      final signedEvent = await signFuture.timeout(_signAttemptTimeout);
      await _handleSignSuccess(
        attemptId: attemptId,
        record: attemptingRecord,
        event: event,
        signedEvent: signedEvent,
      );
      _clearActiveSignAttempt(event.id, attemptId: attemptId);
      return true;
    } on TimeoutException catch (_) {
      _clearActiveSignAttempt(event.id, attemptId: attemptId);
      _trackLateSigningCompletion(
        attemptId: attemptId,
        event: event,
        record: attemptingRecord,
        future: signFuture,
      );

      final waitingForApproval = _hasPendingSignerRequest(signer, event.id);
      await _saveSigningOutcome(
        attemptingRecord.copyWith(
          signingState: waitingForApproval
              ? EventSigningState.needsAction
              : EventSigningState.transientFailure,
          updatedAt: Nip01Event.secondsSinceEpoch(),
          nextSignRetryAt: waitingForApproval
              ? null
              : Nip01Event.secondsSinceEpoch() +
                    _signRetryDelayFor(
                      attemptCount: attemptingRecord.signAttemptCount,
                      requiresSignerNetwork: signer.requiresSignerNetwork,
                    ).inSeconds,
          lastSignError: waitingForApproval
              ? 'Waiting for signer approval'
              : 'Timed out waiting for signer',
        ),
      );
      return false;
    } catch (error, stackTrace) {
      await _handleSignFailure(
        attemptId: attemptId,
        record: attemptingRecord,
        event: event,
        signer: signer,
        error: error,
        stackTrace: stackTrace,
      );
      _clearActiveSignAttempt(event.id, attemptId: attemptId);
      return false;
    }
  }

  void _trackLateSigningCompletion({
    required int attemptId,
    required Nip01Event event,
    required EventDeliveryRecord record,
    required Future<Nip01Event> future,
  }) {
    unawaited(
      future
          .then(
            (signedEvent) async {
              await _handleSignSuccess(
                attemptId: attemptId,
                record: record,
                event: event,
                signedEvent: signedEvent,
              );
            },
            onError: (Object error, StackTrace stackTrace) async {
              await _handleSignFailure(
                attemptId: attemptId,
                record: record,
                event: event,
                signer: _resolveSignerForEvent(event),
                error: error,
                stackTrace: stackTrace,
              );
            },
          )
          .whenComplete(() {
            _clearActiveSignAttempt(event.id, attemptId: attemptId);
          }),
    );
  }

  Future<void> _handleSignSuccess({
    required int attemptId,
    required EventDeliveryRecord record,
    required Nip01Event event,
    required Nip01Event signedEvent,
  }) async {
    if (_stopped) {
      return;
    }
    if (!_isLatestSignAttempt(event.id, attemptId)) {
      return;
    }
    if (await _isObsoleteReplaceableOrAddressableEvent(event)) {
      await _discardEventDelivery(event.id);
      return;
    }

    final now = Nip01Event.secondsSinceEpoch();
    await _store.saveEvent(signedEvent);
    await _saveSigningOutcome(
      record.copyWith(
        signingState: EventSigningState.signed,
        updatedAt: now,
        serializedEventJson: _serializeEvent(signedEvent),
        signedAt: now,
        nextSignRetryAt: null,
        lastSignError: null,
      ),
    );

    await _flushConnectedTargetsForEvent(event.id);
  }

  Future<void> _handleSignFailure({
    required int attemptId,
    required EventDeliveryRecord record,
    required Nip01Event event,
    required EventSigner? signer,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    if (_stopped) {
      return;
    }
    if (!_isLatestSignAttempt(event.id, attemptId)) {
      return;
    }
    Logger.log.w(
      () => 'remote signing failed for ${event.id}',
      error: error,
      stackTrace: stackTrace,
    );

    final outcome = _classifySigningFailure(error);
    final now = Nip01Event.secondsSinceEpoch();
    final nextRetryAt = outcome == EventSigningState.transientFailure
        ? now +
              _signRetryDelayFor(
                attemptCount: record.signAttemptCount,
                requiresSignerNetwork: signer?.requiresSignerNetwork ?? false,
              ).inSeconds
        : null;

    await _saveSigningOutcome(
      record.copyWith(
        signingState: outcome,
        updatedAt: now,
        nextSignRetryAt: nextRetryAt,
        lastSignError: error.toString(),
      ),
    );
  }

  bool _isLatestSignAttempt(String eventId, int attemptId) {
    return _latestSignAttemptIds[eventId] == attemptId;
  }

  void _clearActiveSignAttempt(String eventId, {required int attemptId}) {
    if (_activeSignAttemptIds[eventId] == attemptId) {
      _activeSignAttemptIds.remove(eventId);
    }
  }

  EventSigningState _classifySigningFailure(Object error) {
    if (error is SignerRequestCancelledException ||
        error is SignerRequestRejectedException) {
      return EventSigningState.needsAction;
    }

    final normalized = error.toString().toLowerCase();
    if (normalized.contains('not available') ||
        normalized.contains('not installed') ||
        normalized.contains('requires action') ||
        normalized.contains('approval') ||
        normalized.contains('permission') ||
        normalized.contains('use getpublickeyasync') ||
        normalized.contains('cannot sign') ||
        normalized.contains('unknown account')) {
      return EventSigningState.needsAction;
    }

    if (normalized.contains('unsupported') ||
        normalized.contains('invalid event') ||
        normalized.contains('bad signature')) {
      return EventSigningState.permanentFailure;
    }

    return EventSigningState.transientFailure;
  }

  Duration _signRetryDelayFor({
    required int attemptCount,
    required bool requiresSignerNetwork,
  }) {
    final retrySeconds = requiresSignerNetwork
        ? switch (attemptCount) {
            <= 1 => 15,
            2 => 60,
            3 => 300,
            4 => 900,
            _ => 1800,
          }
        : switch (attemptCount) {
            <= 1 => 5,
            2 => 15,
            3 => 60,
            4 => 300,
            _ => 900,
          };
    return Duration(seconds: retrySeconds);
  }

  bool _hasPendingSignerRequest(EventSigner signer, String eventId) {
    return signer.pendingRequests.any(
      (request) =>
          request.method == SignerMethod.signEvent &&
          request.event?.id == eventId,
    );
  }

  EventSigner? _resolveSignerForEvent(Nip01Event event) {
    final account = _accounts.accounts[event.pubKey];
    return account?.signer;
  }

  bool _isSignerTransportReachable(EventSigner signer) {
    final transportRelayUrls = signer.signerTransportRelayUrls.toSet();
    if (transportRelayUrls.isEmpty) {
      return true;
    }

    final connectedRelayUrls =
        _connectedRelayUrlsProvider?.call().toSet() ?? {};
    return transportRelayUrls.any(connectedRelayUrls.contains);
  }

  Future<void> _flushConnectedTargetsForEvent(String eventId) async {
    if (_stopped) {
      return;
    }
    final connectedRelayUrls = _connectedRelayUrlsProvider?.call().toSet();
    if (connectedRelayUrls == null || connectedRelayUrls.isEmpty) {
      return;
    }

    final targets = await _store.loadRelayDeliveryTargets(eventId: eventId);
    final targetRelayUrls =
        targets
            .where((target) => connectedRelayUrls.contains(target.relayUrl))
            .map((target) => target.relayUrl)
            .toSet()
            .toList()
          ..sort();

    for (final relayUrl in targetRelayUrls) {
      await flushForRelay(relayUrl);
    }
  }

  Future<void> _markEventSigned(EventDeliveryRecord record) async {
    final now = Nip01Event.secondsSinceEpoch();
    await _saveSigningOutcome(
      record.copyWith(
        signingState: EventSigningState.signed,
        updatedAt: now,
        signedAt: now,
        nextSignRetryAt: null,
        lastSignError: null,
      ),
    );
  }

  Future<void> _saveSigningOutcome(EventDeliveryRecord record) async {
    final targets = await _store.loadRelayDeliveryTargets(
      eventId: record.eventId,
    );
    final resolvedStatus = _resolveDeliveryStatus(record, targets);
    final now = Nip01Event.secondsSinceEpoch();
    await _store.saveEventDeliveryRecord(
      record.copyWith(
        status: resolvedStatus,
        completedAt: resolvedStatus == EventDeliveryStatus.delivered
            ? (record.completedAt ?? now)
            : null,
      ),
    );
    _dropSettledAuthPolicies(targets);
    await _purgeEphemeralIfResolved(
      record.eventId,
      resolvedStatus,
      _resolveEventKindFromRecord(record),
      targets,
    );
  }

  /// Ephemeral events carry no lasting cache value. Once their delivery reaches
  /// a fully-resolved state, drop the event and every
  /// eventId-keyed sidecar immediately, instead of waiting for a background
  /// eviction pass. [removeEvent] wipes the event plus its sources, delivery
  /// record, relay delivery targets, decrypted payloads and state record.
  Future<void> _purgeEphemeralIfResolved(
    String eventId,
    EventDeliveryStatus status,
    int? kind,
    List<RelayDeliveryTarget> targets,
  ) async {
    final isResolved =
        status == EventDeliveryStatus.delivered ||
        status == EventDeliveryStatus.failed ||
        (status == EventDeliveryStatus.partiallyDelivered &&
            targets.isNotEmpty &&
            targets.every(
              (t) =>
                  t.state == RelayDeliveryState.acked ||
                  t.state == RelayDeliveryState.permanentFailure,
            ));
    if (!isResolved) {
      return;
    }
    if (kind == null || !EventKindClassification.isEphemeralKind(kind)) {
      return;
    }
    await _store.removeEvent(eventId);
  }

  int? _resolveEventKindFromRecord(EventDeliveryRecord record) {
    final json = record.serializedEventJson;
    if (json == null || json.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map && decoded['kind'] is int) {
        return decoded['kind'] as int;
      }
    } catch (_) {}
    return null;
  }

  bool _isAddressableKind(int kind) {
    return EventKindClassification.isAddressableKind(kind);
  }

  Future<Nip01Event?> _loadRecoverableEvent(
    String eventId, {
    required EventDeliveryRecord record,
  }) async {
    final cachedEvent = await _store.loadEvent(eventId);
    if (cachedEvent != null) {
      return cachedEvent;
    }

    final serializedEventJson = record.serializedEventJson;
    if (serializedEventJson == null || serializedEventJson.isEmpty) {
      return null;
    }

    try {
      final parsedEvent = Nip01Event.fromJson(
        jsonDecode(serializedEventJson) as Map<String, dynamic>,
      );
      await _store.saveEvent(parsedEvent);
      return parsedEvent;
    } catch (error, stackTrace) {
      Logger.log.w(
        () => 'failed to restore serialized pending-delivery event $eventId',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  String? _serializeEvent(Nip01Event event) {
    try {
      return event.toJsonString();
    } catch (_) {
      return null;
    }
  }

  EventDeliveryStatus _resolveDeliveryStatus(
    EventDeliveryRecord record,
    List<RelayDeliveryTarget> targets,
  ) {
    if (record.requiresInteractiveSigning &&
        record.signingState != EventSigningState.signed &&
        record.signedAt == null) {
      return switch (record.signingState) {
        EventSigningState.needsAction => EventDeliveryStatus.needsAction,
        EventSigningState.permanentFailure => EventDeliveryStatus.failed,
        EventSigningState.pending => EventDeliveryStatus.pending,
        EventSigningState.notNeeded => EventDeliveryStatus.pending,
        EventSigningState.attempting ||
        EventSigningState.transientFailure => EventDeliveryStatus.inProgress,
        EventSigningState.signed => EventDeliveryStatus.inProgress,
      };
    }

    if (targets.isEmpty) {
      return EventDeliveryStatus.pending;
    }

    final waitsForUrlSets = record.unresolvedUrlSets.isNotEmpty;
    final allAcked = targets.every((t) => t.state == RelayDeliveryState.acked);
    if (allAcked) {
      return waitsForUrlSets
          ? EventDeliveryStatus.partiallyDelivered
          : EventDeliveryStatus.delivered;
    }

    if (targets.any((t) => t.state == RelayDeliveryState.authRequired)) {
      return EventDeliveryStatus.needsAction;
    }

    final ackedCount = targets
        .where((t) => t.state == RelayDeliveryState.acked)
        .length;
    final permanentFailureCount = targets
        .where((t) => t.state == RelayDeliveryState.permanentFailure)
        .length;

    final allTerminal = targets.every(
      (t) =>
          t.state == RelayDeliveryState.acked ||
          t.state == RelayDeliveryState.permanentFailure,
    );
    if (allTerminal && !waitsForUrlSets) {
      return ackedCount > 0
          ? EventDeliveryStatus.partiallyDelivered
          : EventDeliveryStatus.failed;
    }

    if (ackedCount > 0 || permanentFailureCount > 0) {
      return EventDeliveryStatus.partiallyDelivered;
    }

    return EventDeliveryStatus.inProgress;
  }
}

/// Outcome of rebuilding a persisted auth policy.
///
/// A null [policy] is the historical default, "authenticate as whoever the
/// relay manager picks". [unavailable] is different: the caller named an
/// identity and nobody here can sign for it, so nothing may be sent.
class _AuthResolution {
  final AuthPolicy? policy;

  /// false only for [unavailable]; a const `never` policy would otherwise be
  /// canonically identical to it
  final bool available;

  const _AuthResolution(this.policy) : available = true;

  const _AuthResolution._unavailable() : policy = null, available = false;

  /// the named identity is gone, so this delivery has to wait for it
  static const _AuthResolution unavailable = _AuthResolution._unavailable();
}
