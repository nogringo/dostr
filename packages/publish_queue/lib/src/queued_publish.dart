import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_url_set/dostr_url_set.dart';

/// Status of a queued publish.
enum QueuedPublishStatus {
  /// At least one targeted relay has not accepted the event yet.
  pending,

  /// Every relay has either accepted the event or refused it for good: a
  /// terminal NIP-01 OK prefix, an event too long for it, a relay the
  /// `RelayManager` blocks, or too many online attempts while unreachable.
  failed,

  /// Every relay in `relays` has accepted the event at least once.
  /// Monotonic: once a record reaches this state the queue never demotes it
  /// back to `pending` on its own.
  delivered,

  /// Newer versions of the same replaceable or addressable event hold, or are
  /// headed to, every relay this one still owed, so it is no longer retried.
  /// See [QueuedPublish.supersededBy].
  superseded,

  /// The caller stopped its retries with `PublishQueue.cancel` before it
  /// was settled. See [QueuedPublish.cancelledAt].
  cancelled,
}

/// A single publish tracked by `PublishQueue`.
///
/// Immutable from the caller's perspective: every mutation goes through the
/// store and yields a fresh instance.
class QueuedPublish {
  /// Nostr event id. Combined with [account] it forms the record [key].
  final String id;

  /// Pubkey of the local account this publish was queued under, or `null`
  /// if the caller did not attribute it. It need not be `event.pubkey`: an
  /// event can be queued under an account that did not sign it
  /// (republishing someone else's note), and for a gift wrap (kind 1059)
  /// `event.pubkey` is an ephemeral throwaway key. It is part of the record's
  /// identity, so the same event queued under two accounts is two independent
  /// records. `PublishQueue.clearLocalAccountData` matches on this field.
  final String? account;

  /// The full event, as it is published.
  final Nip01Event event;

  /// The relays this event must reach. Grows when [pendingRelaySet]
  /// resolves, when `publish` merges more relays, or when
  /// `republish(id, relay: ...)` introduces a new relay.
  final List<RelayUrl> relays;

  /// Relay set still to resolve, or `null` once its relays are frozen into
  /// [relays]. While non-null the record is [QueuedPublishStatus.pending].
  final UrlSet? pendingRelaySet;

  /// Consecutive resolutions of [pendingRelaySet] that ended unavailable.
  /// Drives the backoff until the set resolves.
  final int resolutionAttempts;

  /// Why the last resolution did not produce relays: a lookup was unavailable,
  /// or the set resolved to no relay at all. `null` otherwise.
  final String? resolutionError;

  /// Subset of [relays] that have accepted the event at least once across all
  /// attempts.
  final List<RelayUrl> ackedRelays;

  /// Last error seen per relay still pending. Cleared on ack.
  final Map<RelayUrl, String> lastErrors;

  /// Why each relay refused the event for good. These relays are no longer
  /// retried automatically for this event.
  final Map<RelayUrl, String> terminalErrors;

  /// Consecutive online attempts where a relay was unreachable. Reset when the
  /// relay answers.
  final Map<RelayUrl, int> inaccessibleAttempts;

  /// Number of delivery attempts that have completed (success or failure)
  /// since the record was created.
  final int attempts;

  /// Online attempts that left relays owed since the record was last queued
  /// by `publish` or given a new relay by `republish`. Drives the backoff:
  /// an offline attempt leaves it unchanged.
  final int onlineFailures;

  /// Wall-clock millis (since epoch) of the first attempt for this record,
  /// or null if none has run yet.
  final int? firstAttemptAt;

  /// Wall-clock millis (since epoch) of the most recent attempt, or null if
  /// none has run yet.
  final int? lastAttemptAt;

  /// Wall-clock millis (since epoch) at which the worker should attempt this
  /// record next. The periodic tick picks up records whose value is <= now.
  final int nextAttemptAt;

  /// Wall-clock millis (since epoch) of the first time every relay in
  /// [relays] had accepted the event. Monotonic: once set, never cleared by
  /// an attempt; only `republish(id, relay: r)` with a brand new relay (or
  /// `publish()` merging in an unacked relay) clears it.
  final int? deliveredAt;

  /// Wall-clock millis (since epoch) of the first time the entry became
  /// terminally failed: all relays were either acked or terminally rejected,
  /// with at least one terminal rejection.
  final int? failedAt;

  /// Wall-clock millis (since epoch) when this record was first persisted.
  final int createdAt;

  /// Override for the *next* attempt only: when non-null, the worker pushes
  /// the event to exactly these relays, even if some of them already have
  /// acks. Set by `PublishQueue.republish`; cleared by the attempt itself
  /// once it runs. Existence is what makes a delivered entry eligible for one
  /// more push without rewriting its history.
  final List<RelayUrl>? forcedRelays;

  /// Id of the newest version of this replaceable or addressable event when
  /// newer versions stopped its retries, or `null`. Set once and never
  /// cleared: the record stays [QueuedPublishStatus.superseded] whatever
  /// happens to those versions.
  final String? supersededBy;

  /// Wall-clock millis (since epoch) when `PublishQueue.cancel` stopped
  /// this record's retries, or `null`. Cleared when `publish` queues the
  /// same record again.
  final int? cancelledAt;

  /// Creates a record. Most callers should not invoke this directly; records
  /// are produced by `PublishQueue`.
  QueuedPublish({
    required this.id,
    this.account,
    required this.event,
    required this.relays,
    this.pendingRelaySet,
    this.resolutionAttempts = 0,
    this.resolutionError,
    required this.ackedRelays,
    required this.lastErrors,
    required this.terminalErrors,
    required this.inaccessibleAttempts,
    required this.attempts,
    this.onlineFailures = 0,
    required this.firstAttemptAt,
    required this.lastAttemptAt,
    required this.nextAttemptAt,
    required this.deliveredAt,
    required this.failedAt,
    required this.createdAt,
    this.forcedRelays,
    this.supersededBy,
    this.cancelledAt,
  });

  /// The key that identifies this record in its store.
  String get key => keyFor(eventId: id, account: account);

  /// Builds the record key for an (event, account) pair:
  /// `account|eventId` when bound to an account, the bare event id otherwise.
  static String keyFor({required String eventId, String? account}) =>
      account == null ? eventId : '$account|$eventId';

  /// `pending` while the relay set is unresolved or any relay is still
  /// retryable, otherwise terminal.
  QueuedPublishStatus get status {
    if (supersededBy != null) return QueuedPublishStatus.superseded;
    if (cancelledAt != null) return QueuedPublishStatus.cancelled;
    if (pendingRelaySet != null) return QueuedPublishStatus.pending;
    if (deliveredAt != null) return QueuedPublishStatus.delivered;
    if (failedAt != null) return QueuedPublishStatus.failed;
    return QueuedPublishStatus.pending;
  }

  /// Relays still retryable, i.e. [relays] minus acks and terminal failures.
  List<RelayUrl> get remainingRelays {
    final acked = ackedRelays.toSet();
    final terminal = terminalErrors.keys.toSet();
    return relays
        .where((r) => !acked.contains(r) && !terminal.contains(r))
        .toList(growable: false);
  }

  /// Returns a copy of this record with the given fields replaced.
  ///
  /// Use `clearDelivered: true` to force-clear [deliveredAt] (`null` arg
  /// alone is ambiguous with "leave as-is" for nullable fields). Same idea
  /// for `clearForcedRelays`, `clearPendingRelaySet`, `clearResolutionError`
  /// and `clearCancelled`.
  QueuedPublish copyWith({
    List<RelayUrl>? relays,
    UrlSet? pendingRelaySet,
    int? resolutionAttempts,
    String? resolutionError,
    List<RelayUrl>? ackedRelays,
    Map<RelayUrl, String>? lastErrors,
    Map<RelayUrl, String>? terminalErrors,
    Map<RelayUrl, int>? inaccessibleAttempts,
    int? attempts,
    int? onlineFailures,
    int? firstAttemptAt,
    int? lastAttemptAt,
    int? nextAttemptAt,
    int? deliveredAt,
    int? failedAt,
    List<RelayUrl>? forcedRelays,
    String? supersededBy,
    int? cancelledAt,
    bool clearDelivered = false,
    bool clearFailed = false,
    bool clearForcedRelays = false,
    bool clearPendingRelaySet = false,
    bool clearResolutionError = false,
    bool clearCancelled = false,
  }) {
    return QueuedPublish(
      id: id,
      account: account,
      event: event,
      relays: relays ?? this.relays,
      pendingRelaySet: clearPendingRelaySet
          ? null
          : (pendingRelaySet ?? this.pendingRelaySet),
      resolutionAttempts: resolutionAttempts ?? this.resolutionAttempts,
      resolutionError: clearResolutionError
          ? null
          : (resolutionError ?? this.resolutionError),
      ackedRelays: ackedRelays ?? this.ackedRelays,
      lastErrors: lastErrors ?? this.lastErrors,
      terminalErrors: terminalErrors ?? this.terminalErrors,
      inaccessibleAttempts: inaccessibleAttempts ?? this.inaccessibleAttempts,
      attempts: attempts ?? this.attempts,
      onlineFailures: onlineFailures ?? this.onlineFailures,
      firstAttemptAt: firstAttemptAt ?? this.firstAttemptAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      deliveredAt: clearDelivered ? null : (deliveredAt ?? this.deliveredAt),
      failedAt: clearFailed ? null : (failedAt ?? this.failedAt),
      createdAt: createdAt,
      forcedRelays: clearForcedRelays
          ? null
          : (forcedRelays ?? this.forcedRelays),
      supersededBy: supersededBy ?? this.supersededBy,
      cancelledAt: clearCancelled ? null : (cancelledAt ?? this.cancelledAt),
    );
  }

  /// Serializes the record as JSON-compatible values.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pubkey': account,
      'event': event.toJson(),
      'relays': relays,
      'pendingRelaySet': pendingRelaySet?.toMap(),
      'resolutionAttempts': resolutionAttempts,
      'resolutionError': resolutionError,
      'ackedRelays': ackedRelays,
      'lastErrors': lastErrors,
      'terminalErrors': terminalErrors,
      'inaccessibleAttempts': inaccessibleAttempts,
      'attempts': attempts,
      'onlineFailures': onlineFailures,
      'firstAttemptAt': firstAttemptAt,
      'lastAttemptAt': lastAttemptAt,
      'nextAttemptAt': nextAttemptAt,
      'deliveredAt': deliveredAt,
      'failedAt': failedAt,
      'createdAt': createdAt,
      'forcedRelays': forcedRelays,
      'supersededBy': supersededBy,
      'cancelledAt': cancelledAt,
    };
  }

  /// Inverse of [toMap]. Reads the records of `broadcast_queue_shim_for_ndk`
  /// too, and drops the relay urls that are not ws or wss urls.
  static QueuedPublish fromMap(Map<String, dynamic> map) {
    return QueuedPublish(
      id: map['id'] as String,
      account: map['pubkey'] as String?,
      event: Nip01Event.fromJson(map['event'] as Map),
      relays: _relayList(map['relays']),
      pendingRelaySet: map['pendingRelaySet'] == null
          ? null
          : UrlSet.fromMap(map['pendingRelaySet'] as Map),
      resolutionAttempts: (map['resolutionAttempts'] as int?) ?? 0,
      resolutionError: map['resolutionError'] as String?,
      ackedRelays: _relayList(map['ackedRelays']),
      lastErrors: _relayMap<String>(map['lastErrors']),
      terminalErrors: _relayMap<String>(map['terminalErrors']),
      inaccessibleAttempts: _relayMap<int>(map['inaccessibleAttempts']),
      attempts: map['attempts'] as int,
      onlineFailures: (map['onlineFailures'] as int?) ?? 0,
      firstAttemptAt: map['firstAttemptAt'] as int?,
      lastAttemptAt: map['lastAttemptAt'] as int?,
      nextAttemptAt: map['nextAttemptAt'] as int,
      deliveredAt: map['deliveredAt'] as int?,
      failedAt: map['failedAt'] as int?,
      createdAt: map['createdAt'] as int,
      forcedRelays: map['forcedRelays'] == null
          ? null
          : _relayList(map['forcedRelays']),
      supersededBy: map['supersededBy'] as String?,
      cancelledAt: map['cancelledAt'] as int?,
    );
  }

  static List<RelayUrl> _relayList(Object? urls) => [
    for (final url in (urls as List?) ?? const [])
      ?RelayUrl.tryParse(url as String),
  ];

  static Map<RelayUrl, T> _relayMap<T>(Object? map) => {
    for (final MapEntry(:key, :value) in ((map as Map?) ?? const {}).entries)
      ?RelayUrl.tryParse(key as String): value as T,
  };
}
