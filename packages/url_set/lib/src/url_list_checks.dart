/// When the relays were last asked for one list of an account, and whether
/// they held it. The list itself stays in the event cache.
class UrlListCheck {
  /// Account whose list was asked for.
  final String pubkey;

  /// Event kind of the list, such as 10002 or 10050.
  final int kind;

  /// The `d` tag of an addressable list, null for a replaceable one.
  final String? dTag;

  /// When a relay last answered the query.
  final DateTime checkedAt;

  /// Whether the list existed then.
  final bool found;

  /// Creates a check.
  const UrlListCheck({
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
  factory UrlListCheck.fromMap(Map map) => UrlListCheck(
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

/// Where a lookup keeps its [UrlListCheck]s, one per pubkey, kind and d tag.
/// Implement it on the database the app already has to keep them across
/// restarts. [UrlListCheck.toMap] gives a JSON-compatible record.
abstract interface class UrlListCheckStore {
  /// The check of the [kind] list of [pubkey], named [dTag] if addressable,
  /// or null if it never ran.
  Future<UrlListCheck?> read(String pubkey, int kind, {String? dTag});

  /// Replaces the check of the same pubkey, kind and d tag.
  Future<void> write(UrlListCheck check);
}

/// A [UrlListCheckStore] that lives as long as the process.
class MemoryUrlListCheckStore implements UrlListCheckStore {
  final _checks = <(String, int, String?), UrlListCheck>{};

  @override
  Future<UrlListCheck?> read(String pubkey, int kind, {String? dTag}) async =>
      _checks[(pubkey, kind, dTag)];

  @override
  Future<void> write(UrlListCheck check) async =>
      _checks[(check.pubkey, check.kind, check.dTag)] = check;
}
