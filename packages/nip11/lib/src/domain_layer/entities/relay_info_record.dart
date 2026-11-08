import 'relay_info.dart';

/// What the relay at [url] answered at [fetchedAt], as a `RelayInfoCache`
/// keeps it
class RelayInfoRecord {
  /// the url the relay was asked under, the key of the record
  final String url;

  /// null when the relay answered without a document
  final RelayInfo? info;

  /// in UTC and to the millisecond, as [toJson] keeps it, so a record reads
  /// back equal
  final DateTime fetchedAt;

  RelayInfoRecord({required this.url, this.info, required DateTime fetchedAt})
    : fetchedAt = DateTime.fromMillisecondsSinceEpoch(
        fetchedAt.millisecondsSinceEpoch,
        isUtc: true,
      );

  /// [json] can be any `Map`, such as one a Hive box gives back
  factory RelayInfoRecord.fromJson(Map json) => RelayInfoRecord(
    url: json['url'] as String,
    info: switch (json['info']) {
      final Map info => RelayInfo.fromJson(info),
      _ => null,
    },
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['fetched_at'] as num).toInt(),
      isUtc: true,
    ),
  );

  /// [fetchedAt] in milliseconds since the epoch
  Map<String, dynamic> toJson() => {
    'url': url,
    'info': ?info?.toJson(),
    'fetched_at': fetchedAt.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is RelayInfoRecord &&
      other.url == url &&
      other.info == info &&
      other.fetchedAt == fetchedAt;

  @override
  int get hashCode => Object.hash(url, info, fetchedAt);

  @override
  String toString() => 'RelayInfoRecord${toJson()}';
}
