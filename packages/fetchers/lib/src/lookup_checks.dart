/// When the relays were last asked for one replaceable event of an account,
/// such as its metadata or a relay list, and whether they held it. The event
/// itself stays in the [ReplaceableEventCache].
class LookupCheck {
  /// Account whose event was asked for.
  final String pubkey;

  /// Kind of the event, such as 0, 10002 or 10050.
  final int kind;

  /// The `d` tag of an addressable event, null for a replaceable one.
  final String? dTag;

  /// When a relay last answered the query.
  final DateTime checkedAt;

  /// Whether the event existed then.
  final bool found;

  /// Creates a check.
  const LookupCheck({
    required this.pubkey,
    required this.kind,
    this.dTag,
    required this.checkedAt,
    required this.found,
  });

  /// Serializes the check for storage.
  Map<String, Object?> toMap() => {
    'pubkey': pubkey,
    'kind': kind,
    'dTag': ?dTag,
    'checkedAt': checkedAt.millisecondsSinceEpoch,
    'found': found,
  };

  /// Inverse of [toMap].
  factory LookupCheck.fromMap(Map map) => LookupCheck(
    pubkey: map['pubkey'] as String,
    kind: map['kind'] as int,
    dTag: map['dTag'] as String?,
    checkedAt: DateTime.fromMillisecondsSinceEpoch(
      map['checkedAt'] as int,
      isUtc: true,
    ),
    found: map['found'] as bool,
  );
}

/// Where a lookup keeps its [LookupCheck]s, one per pubkey, kind and d tag.
/// Implement it on the database the app already has to keep them across
/// restarts. [LookupCheck.toMap] gives a JSON-compatible record.
abstract interface class LookupCheckStore {
  /// The check of the [kind] event of [pubkey], named [dTag] if addressable,
  /// or null if it never ran.
  Future<LookupCheck?> read({
    required int kind,
    required String pubkey,
    String? dTag,
  });

  /// Replaces the check of the same pubkey, kind and d tag.
  Future<void> write(LookupCheck check);
}

/// A [LookupCheckStore] that lives as long as the process.
class MemoryLookupCheckStore implements LookupCheckStore {
  final _checks = <(String, int, String?), LookupCheck>{};

  @override
  Future<LookupCheck?> read({
    required int kind,
    required String pubkey,
    String? dTag,
  }) async => _checks[(pubkey, kind, dTag)];

  @override
  Future<void> write(LookupCheck check) async =>
      _checks[(check.pubkey, check.kind, check.dTag)] = check;
}
