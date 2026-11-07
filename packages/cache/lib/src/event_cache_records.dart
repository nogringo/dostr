import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_core/shared/nips/nip01/event_kind_classification.dart';

const _noChange = Object();

enum DecryptedPayloadScheme { nip04, nip44, giftWrap, seal, unknown }

/// Result of attempting to obtain plaintext for an encrypted payload sidecar.
enum DecryptedPayloadStatus { ready, transientFailure, permanentFailure }

/// Sidecar cache record for decrypted event plaintext.
///
/// NDK intentionally does not mutate the original encrypted [Nip01Event] with
/// decrypted content. Instead it stores a separate plaintext sidecar keyed by
/// `(eventId, viewerPubKey)`.
class DecryptedEventPayloadRecord {
  final String eventId;
  final String viewerPubKey;
  final DecryptedPayloadScheme scheme;
  final DecryptedPayloadStatus status;
  final String? plaintextContent;
  final int createdAt;
  final int updatedAt;
  final int? decryptedAt;
  final String? failureReason;
  final String? sourceEventPubKey;
  final int? sourceEventKind;

  const DecryptedEventPayloadRecord({
    required this.eventId,
    required this.viewerPubKey,
    this.scheme = DecryptedPayloadScheme.unknown,
    this.status = DecryptedPayloadStatus.ready,
    this.plaintextContent,
    required this.createdAt,
    required this.updatedAt,
    this.decryptedAt,
    this.failureReason,
    this.sourceEventPubKey,
    this.sourceEventKind,
  });

  /// Stable primary key used by cache backends.
  String get key => '$eventId|$viewerPubKey';

  DecryptedEventPayloadRecord copyWith({
    String? eventId,
    String? viewerPubKey,
    DecryptedPayloadScheme? scheme,
    DecryptedPayloadStatus? status,
    Object? plaintextContent = _noChange,
    int? createdAt,
    int? updatedAt,
    Object? decryptedAt = _noChange,
    Object? failureReason = _noChange,
    Object? sourceEventPubKey = _noChange,
    Object? sourceEventKind = _noChange,
  }) {
    return DecryptedEventPayloadRecord(
      eventId: eventId ?? this.eventId,
      viewerPubKey: viewerPubKey ?? this.viewerPubKey,
      scheme: scheme ?? this.scheme,
      status: status ?? this.status,
      plaintextContent: identical(plaintextContent, _noChange)
          ? this.plaintextContent
          : plaintextContent as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      decryptedAt: identical(decryptedAt, _noChange)
          ? this.decryptedAt
          : decryptedAt as int?,
      failureReason: identical(failureReason, _noChange)
          ? this.failureReason
          : failureReason as String?,
      sourceEventPubKey: identical(sourceEventPubKey, _noChange)
          ? this.sourceEventPubKey
          : sourceEventPubKey as String?,
      sourceEventKind: identical(sourceEventKind, _noChange)
          ? this.sourceEventKind
          : sourceEventKind as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'viewerPubKey': viewerPubKey,
      'scheme': scheme.name,
      'status': status.name,
      'plaintextContent': plaintextContent,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'decryptedAt': decryptedAt,
      'failureReason': failureReason,
      'sourceEventPubKey': sourceEventPubKey,
      'sourceEventKind': sourceEventKind,
    };
  }

  factory DecryptedEventPayloadRecord.fromJson(Map<String, dynamic> json) {
    return DecryptedEventPayloadRecord(
      eventId: json['eventId'] as String,
      viewerPubKey: json['viewerPubKey'] as String,
      scheme: json['scheme'] != null
          ? DecryptedPayloadScheme.values.byName(json['scheme'] as String)
          : DecryptedPayloadScheme.unknown,
      status: json['status'] != null
          ? DecryptedPayloadStatus.values.byName(json['status'] as String)
          : DecryptedPayloadStatus.ready,
      plaintextContent: json['plaintextContent'] as String?,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      decryptedAt: json['decryptedAt'] as int?,
      failureReason: json['failureReason'] as String?,
      sourceEventPubKey: json['sourceEventPubKey'] as String?,
      sourceEventKind: json['sourceEventKind'] as int?,
    );
  }
}

int? _extractExpirationAt(Nip01Event event) {
  final rawValue = event.getFirstTag('expiration');
  if (rawValue == null) return null;
  return int.tryParse(rawValue);
}

String? _buildCoordinateKey(
  Nip01Event event,
  String? dTag,
  bool isAddressable,
) {
  // Coordinate keys identify the conflict domain for replaceable events.
  // For addressable kinds this becomes `kind:pubkey:d-tag`.
  if (!isAddressable) return null;
  return '${event.kind}:${event.pubKey}:${dTag ?? ''}';
}

String? _buildReplaceableConflictKey(Nip01Event event, String? dTag) {
  if (EventKindClassification.isParameterizedReplaceableKind(event.kind)) {
    return '${event.kind}:${event.pubKey}:${dTag ?? ''}';
  }
  if (EventKindClassification.isReplaceableKind(event.kind)) {
    return '${event.kind}:${event.pubKey}';
  }
  return null;
}

bool _isAddressableKind(int kind) {
  return EventKindClassification.isAddressableKind(kind);
}

bool _isMoreRecentEventThan(Nip01Event candidate, Nip01Event current) {
  // Replaceable tie-breaker:
  // 1. newer created_at wins
  // 2. stable event id ordering breaks same-timestamp ties deterministically
  if (candidate.createdAt != current.createdAt) {
    return candidate.createdAt > current.createdAt;
  }

  return candidate.id.compareTo(current.id) < 0;
}

/// Lean derived cache metadata for one event.
///
/// This intentionally does not embed the full [Nip01Event]. It persists only
/// the extra state useful for cache maintenance tasks such as eviction
/// planning.
class EventCacheStateRecord {
  final String eventId;
  final String pubKey;
  final int kind;
  final int createdAt;
  final String? coordinateKey;
  final bool isCurrent;
  final int? expirationAt;
  final String? deletedByEventId;

  const EventCacheStateRecord({
    required this.eventId,
    required this.pubKey,
    required this.kind,
    required this.createdAt,
    this.coordinateKey,
    required this.isCurrent,
    this.expirationAt,
    this.deletedByEventId,
  });

  bool get isDeleted => deletedByEventId != null;

  bool isExpiredAt(int timestamp) =>
      expirationAt != null && expirationAt! <= timestamp;

  /// The NIP-01 conflict domain of [event]: `kind:pubkey:d-tag` for addressable
  /// kinds, `kind:pubkey` for other replaceable kinds, null for the rest.
  static String? conflictKeyFor(Nip01Event event) =>
      _buildReplaceableConflictKey(event, event.dTag);

  /// Normalizes a caller supplied conflict domain so it compares equal to
  /// [conflictKeyFor].
  ///
  /// Accepts NIP-01 `a` tag values, whose d-tag segment is present but empty
  /// for non addressable kinds. Returns null when [coordinate] is malformed or
  /// names a kind that has no conflict domain.
  ///
  /// Only the kind is parsed. NIP-01 mandates lowercase hex for the pubkey and
  /// leaves the d-tag an arbitrary string, so both compare byte for byte the
  /// way a relay compares them.
  static String? normalizeConflictKey(String coordinate) {
    final parts = coordinate.split(':');
    if (parts.length < 2) return null;
    final kind = int.tryParse(parts[0]);
    if (kind == null || parts[1].isEmpty) return null;
    final pubKey = parts[1];

    if (EventKindClassification.isParameterizedReplaceableKind(kind)) {
      final dTag = parts.length > 2 ? parts.sublist(2).join(':') : '';
      return '$kind:$pubKey:$dTag';
    }
    if (!EventKindClassification.isReplaceableKind(kind)) return null;
    // A non addressable kind has no d-tag, so only an empty trailing segment
    // is a spelling of the same domain. Anything else is a different request.
    if (parts.length > 3 || (parts.length == 3 && parts[2].isNotEmpty)) {
      return null;
    }
    return '$kind:$pubKey';
  }

  /// Whether [deletion] covers [conflictKey] through one of its `a` tags.
  ///
  /// Reads the tags directly because [Nip01Event.getTags] trims and lowercases
  /// values, which would drop bytes of the d-tag carried by the coordinate.
  static bool deletionCoversConflictKey(
    Nip01Event deletion,
    String conflictKey,
  ) {
    for (final tag in deletion.tags) {
      if (tag.length > 1 &&
          tag[0] == 'a' &&
          normalizeConflictKey(tag[1]) == conflictKey) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'pubKey': pubKey,
      'kind': kind,
      'createdAt': createdAt,
      'coordinateKey': coordinateKey,
      'isCurrent': isCurrent,
      'expirationAt': expirationAt,
      'deletedByEventId': deletedByEventId,
    };
  }

  factory EventCacheStateRecord.fromJson(Map<String, dynamic> json) {
    return EventCacheStateRecord(
      eventId: json['eventId'] as String,
      pubKey: json['pubKey'] as String,
      kind: json['kind'] as int,
      createdAt: json['createdAt'] as int,
      coordinateKey: json['coordinateKey'] as String?,
      isCurrent: json['isCurrent'] as bool? ?? true,
      expirationAt: json['expirationAt'] as int?,
      deletedByEventId: json['deletedByEventId'] as String?,
    );
  }

  /// Builds derived state records from raw events using the same visibility
  /// semantics as cache reads and eviction planning.
  static List<EventCacheStateRecord> buildForEvents(
    List<Nip01Event> rawEvents, {
    int? now,
  }) {
    final currentTime = now ?? Nip01Event.secondsSinceEpoch();
    final deletionEvents = rawEvents
        .where((event) => event.kind == 5)
        .toList(growable: false);
    final visibleWinners = <String, Nip01Event>{};

    for (final event in rawEvents) {
      final replaceableConflictKey = _buildReplaceableConflictKey(
        event,
        event.dTag,
      );
      if (replaceableConflictKey == null) {
        continue;
      }
      if (_extractExpirationAt(event) case final expirationAt?
          when expirationAt <= currentTime) {
        continue;
      }
      if (_findDeletingEvent(event, deletionEvents) != null) {
        continue;
      }

      final current = visibleWinners[replaceableConflictKey];
      if (current == null || _isMoreRecentEventThan(event, current)) {
        visibleWinners[replaceableConflictKey] = event;
      }
    }

    final records = <EventCacheStateRecord>[];
    for (final event in rawEvents) {
      final coordinateKey = _buildCoordinateKey(
        event,
        event.dTag,
        _isAddressableKind(event.kind),
      );
      final replaceableConflictKey = _buildReplaceableConflictKey(
        event,
        event.dTag,
      );
      final deletingEvent = _findDeletingEvent(event, deletionEvents);
      records.add(
        EventCacheStateRecord(
          eventId: event.id,
          pubKey: event.pubKey,
          kind: event.kind,
          createdAt: event.createdAt,
          coordinateKey: coordinateKey,
          isCurrent: replaceableConflictKey == null
              ? true
              : visibleWinners[replaceableConflictKey]?.id == event.id,
          expirationAt: _extractExpirationAt(event),
          deletedByEventId: deletingEvent?.id,
        ),
      );
    }

    return records;
  }

  static Nip01Event? _findDeletingEvent(
    Nip01Event target,
    List<Nip01Event> deletionEvents,
  ) {
    if (target.kind == 5) return null;
    final replaceableConflictKey = _buildReplaceableConflictKey(
      target,
      target.dTag,
    );

    for (final event in deletionEvents) {
      if (event.pubKey != target.pubKey) continue;
      if (event
          .getTags('e')
          .any((id) => id.trim().toLowerCase() == target.id.toLowerCase())) {
        return event;
      }
      if (replaceableConflictKey != null &&
          event.createdAt >= target.createdAt &&
          deletionCoversConflictKey(event, replaceableConflictKey)) {
        return event;
      }
    }

    return null;
  }
}
