import 'dart:convert';

import 'package:ndk_url_set/ndk_url_set.dart';

const _noChange = Object();

/// Aggregate delivery state for one event across all of its relay targets.
enum EventDeliveryStatus {
  pending,
  inProgress,
  partiallyDelivered,
  delivered,
  needsAction,
  failed,
}

/// Persisted signing state for one event before relay delivery can proceed.
enum EventSigningState {
  notNeeded,
  pending,
  attempting,
  signed,
  transientFailure,
  needsAction,
  permanentFailure,
}

/// Per-relay delivery state for one `(eventId, relayUrl)` pair.
enum RelayDeliveryState {
  pending,
  attempting,
  acked,
  transientFailure,
  permanentFailure,
  authRequired,
}

/// Why a relay became a delivery target for an event.
enum RelayDeliveryReason {
  authorWrite,
  authorRead,
  replyAuthorRead,
  mentionRead,
  explicit,
  hint,
}

/// Persisted relay-specific broadcast target.
///
/// NDK stores one record per `(eventId, relayUrl)` pair instead of keeping a
/// mutable list inside an event record. This makes concurrent updates safer and
/// allows retries, acknowledgements, and failures to be tracked independently.
class RelayDeliveryTarget {
  final String eventId;
  final String relayUrl;
  final RelayDeliveryReason reason;
  final RelayDeliveryState state;
  final int attemptCount;
  final int? lastAttemptAt;
  final int? nextRetryAt;
  final String? lastError;
  final String? lastOkMessage;

  /// canonical form of the [AuthPolicy] this event goes to this relay under, see
  /// `AuthPolicy.canonical`. It lives here rather than on the event, because the
  /// same event may be published to two relays under two identities. A signer
  /// cannot be persisted, so only the intent is: the account behind a pubkey is
  /// resolved again on retry.
  final String? authCanonical;

  const RelayDeliveryTarget({
    required this.eventId,
    required this.relayUrl,
    required this.reason,
    this.state = RelayDeliveryState.pending,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.nextRetryAt,
    this.lastError,
    this.lastOkMessage,
    this.authCanonical,
  });

  /// Stable primary key used by cache backends.
  String get key => '${keyPrefixFor(eventId)}$relayUrl';

  /// What [key] of every target of [eventId] starts with, so a caller keyed by
  /// [key] can find them all without spelling the format out again.
  static String keyPrefixFor(String eventId) => '$eventId|';

  RelayDeliveryTarget copyWith({
    String? eventId,
    String? relayUrl,
    RelayDeliveryReason? reason,
    RelayDeliveryState? state,
    int? attemptCount,
    Object? lastAttemptAt = _noChange,
    Object? nextRetryAt = _noChange,
    Object? lastError = _noChange,
    Object? lastOkMessage = _noChange,
    Object? authCanonical = _noChange,
  }) {
    return RelayDeliveryTarget(
      eventId: eventId ?? this.eventId,
      relayUrl: relayUrl ?? this.relayUrl,
      reason: reason ?? this.reason,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: identical(lastAttemptAt, _noChange)
          ? this.lastAttemptAt
          : lastAttemptAt as int?,
      nextRetryAt: identical(nextRetryAt, _noChange)
          ? this.nextRetryAt
          : nextRetryAt as int?,
      lastError: identical(lastError, _noChange)
          ? this.lastError
          : lastError as String?,
      lastOkMessage: identical(lastOkMessage, _noChange)
          ? this.lastOkMessage
          : lastOkMessage as String?,
      authCanonical: identical(authCanonical, _noChange)
          ? this.authCanonical
          : authCanonical as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'relayUrl': relayUrl,
      'reason': reason.name,
      'state': state.name,
      'attemptCount': attemptCount,
      'lastAttemptAt': lastAttemptAt,
      'nextRetryAt': nextRetryAt,
      'lastError': lastError,
      'lastOkMessage': lastOkMessage,
      'authCanonical': authCanonical,
    };
  }

  factory RelayDeliveryTarget.fromJson(Map<String, dynamic> json) {
    return RelayDeliveryTarget(
      eventId: json['eventId'] as String,
      relayUrl: json['relayUrl'] as String,
      reason: RelayDeliveryReason.values.byName(json['reason'] as String),
      state: RelayDeliveryState.values.byName(json['state'] as String),
      attemptCount: json['attemptCount'] as int? ?? 0,
      lastAttemptAt: json['lastAttemptAt'] as int?,
      nextRetryAt: json['nextRetryAt'] as int?,
      lastError: json['lastError'] as String?,
      lastOkMessage: json['lastOkMessage'] as String?,
      authCanonical: json['authCanonical'] as String?,
    );
  }
}

/// A part of a broadcast's [UrlSet] whose lists were unavailable when it went
/// out, kept until it resolves to relays.
class UnresolvedUrlSet {
  final UrlSet urlSet;

  /// canonical form of the `AuthPolicy` the broadcast went out under, which
  /// the relays this part resolves to inherit, see
  /// [RelayDeliveryTarget.authCanonical].
  final String? authCanonical;

  const UnresolvedUrlSet({required this.urlSet, this.authCanonical});

  /// Equal for the same set under the same policy.
  String get key => '${authCanonical ?? ''}|${jsonEncode(urlSet.toMap())}';

  Map<String, dynamic> toJson() {
    return {'urlSet': urlSet.toMap(), 'authCanonical': authCanonical};
  }

  factory UnresolvedUrlSet.fromJson(Map<String, dynamic> json) {
    return UnresolvedUrlSet(
      urlSet: UrlSet.fromMap(json['urlSet'] as Map),
      authCanonical: json['authCanonical'] as String?,
    );
  }
}

/// Persisted aggregate delivery record for one event.
///
/// This record answers "what is the overall delivery state of this event?" and
/// survives process restarts. Detailed per-relay information lives separately in
/// [RelayDeliveryTarget].
class EventDeliveryRecord {
  final String eventId;
  final EventDeliveryStatus status;
  final EventSigningState signingState;
  final int createdAt;
  final int updatedAt;
  final String? serializedEventJson;
  final int? signedAt;
  final int? completedAt;
  final bool requiresInteractiveSigning;
  final int signAttemptCount;
  final int? lastSignAttemptAt;
  final int? nextSignRetryAt;
  final String? lastSignError;

  /// Parts of a broadcast's destinations still waiting for their lists. Once
  /// a part resolves, its relays become [RelayDeliveryTarget]s.
  final List<UnresolvedUrlSet> unresolvedUrlSets;

  const EventDeliveryRecord({
    required this.eventId,
    this.status = EventDeliveryStatus.pending,
    this.signingState = EventSigningState.notNeeded,
    required this.createdAt,
    required this.updatedAt,
    this.serializedEventJson,
    this.signedAt,
    this.completedAt,
    this.requiresInteractiveSigning = false,
    this.signAttemptCount = 0,
    this.lastSignAttemptAt,
    this.nextSignRetryAt,
    this.lastSignError,
    this.unresolvedUrlSets = const [],
  });

  /// True once all known targets have been acknowledged.
  bool get isComplete => status == EventDeliveryStatus.delivered;

  /// True once the event is signed or never required a remote signing phase.
  bool get isSigned =>
      signingState == EventSigningState.signed ||
      (!requiresInteractiveSigning && signedAt == null) ||
      signedAt != null;

  EventDeliveryRecord copyWith({
    String? eventId,
    EventDeliveryStatus? status,
    EventSigningState? signingState,
    int? createdAt,
    int? updatedAt,
    Object? serializedEventJson = _noChange,
    Object? signedAt = _noChange,
    Object? completedAt = _noChange,
    bool? requiresInteractiveSigning,
    int? signAttemptCount,
    Object? lastSignAttemptAt = _noChange,
    Object? nextSignRetryAt = _noChange,
    Object? lastSignError = _noChange,
    List<UnresolvedUrlSet>? unresolvedUrlSets,
  }) {
    return EventDeliveryRecord(
      eventId: eventId ?? this.eventId,
      status: status ?? this.status,
      signingState: signingState ?? this.signingState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      serializedEventJson: identical(serializedEventJson, _noChange)
          ? this.serializedEventJson
          : serializedEventJson as String?,
      signedAt: identical(signedAt, _noChange)
          ? this.signedAt
          : signedAt as int?,
      completedAt: identical(completedAt, _noChange)
          ? this.completedAt
          : completedAt as int?,
      requiresInteractiveSigning:
          requiresInteractiveSigning ?? this.requiresInteractiveSigning,
      signAttemptCount: signAttemptCount ?? this.signAttemptCount,
      lastSignAttemptAt: identical(lastSignAttemptAt, _noChange)
          ? this.lastSignAttemptAt
          : lastSignAttemptAt as int?,
      nextSignRetryAt: identical(nextSignRetryAt, _noChange)
          ? this.nextSignRetryAt
          : nextSignRetryAt as int?,
      lastSignError: identical(lastSignError, _noChange)
          ? this.lastSignError
          : lastSignError as String?,
      unresolvedUrlSets: unresolvedUrlSets ?? this.unresolvedUrlSets,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'status': status.name,
      'signingState': signingState.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'serializedEventJson': serializedEventJson,
      'signedAt': signedAt,
      'completedAt': completedAt,
      'requiresInteractiveSigning': requiresInteractiveSigning,
      'signAttemptCount': signAttemptCount,
      'lastSignAttemptAt': lastSignAttemptAt,
      'nextSignRetryAt': nextSignRetryAt,
      'lastSignError': lastSignError,
      'unresolvedUrlSets': [for (final set in unresolvedUrlSets) set.toJson()],
    };
  }

  factory EventDeliveryRecord.fromJson(Map<String, dynamic> json) {
    final requiresInteractiveSigning =
        json['requiresInteractiveSigning'] as bool? ??
        json['requiresNetworkSigner'] as bool? ??
        false;
    return EventDeliveryRecord(
      eventId: json['eventId'] as String,
      status: EventDeliveryStatus.values.byName(json['status'] as String),
      signingState: json['signingState'] != null
          ? EventSigningState.values.byName(json['signingState'] as String)
          : (requiresInteractiveSigning
                ? EventSigningState.pending
                : EventSigningState.notNeeded),
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      serializedEventJson: json['serializedEventJson'] as String?,
      signedAt: json['signedAt'] as int?,
      completedAt: json['completedAt'] as int?,
      requiresInteractiveSigning: requiresInteractiveSigning,
      signAttemptCount: json['signAttemptCount'] as int? ?? 0,
      lastSignAttemptAt: json['lastSignAttemptAt'] as int?,
      nextSignRetryAt: json['nextSignRetryAt'] as int?,
      lastSignError: json['lastSignError'] as String?,
      unresolvedUrlSets: [
        for (final set in json['unresolvedUrlSets'] as List? ?? const [])
          UnresolvedUrlSet.fromJson((set as Map).cast<String, dynamic>()),
      ],
    );
  }
}
