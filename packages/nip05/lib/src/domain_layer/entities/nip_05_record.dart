import 'nip_05.dart';

/// What the domain of [identifier] gave for it at [fetchedAt], as a
/// `Nip05Cache` keeps it
class Nip05Record {
  /// the identifier as [Nip05.canonicalIdentifier] gives it, the key of the
  /// record
  final String identifier;

  /// null when the domain has no such name
  final Nip05? nip05;

  /// in UTC and to the millisecond, as [toJson] keeps it, so a record reads
  /// back equal
  final DateTime fetchedAt;

  Nip05Record({
    required this.identifier,
    this.nip05,
    required DateTime fetchedAt,
  }) : fetchedAt = DateTime.fromMillisecondsSinceEpoch(
         fetchedAt.millisecondsSinceEpoch,
         isUtc: true,
       );

  /// [json] can be any `Map`, such as one a Hive box gives back
  factory Nip05Record.fromJson(Map json) => Nip05Record(
    identifier: json['identifier'] as String,
    nip05: switch (json['nip05']) {
      final Map nip05 => Nip05.fromJson(nip05),
      _ => null,
    },
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['fetched_at'] as num).toInt(),
      isUtc: true,
    ),
  );

  /// [fetchedAt] in milliseconds since the epoch
  Map<String, dynamic> toJson() => {
    'identifier': identifier,
    'nip05': ?nip05?.toJson(),
    'fetched_at': fetchedAt.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is Nip05Record &&
      other.identifier == identifier &&
      other.nip05 == nip05 &&
      other.fetchedAt == fetchedAt;

  @override
  int get hashCode => Object.hash(identifier, nip05, fetchedAt);

  @override
  String toString() => 'Nip05Record${toJson()}';
}
