import '../entities/relay_info_record.dart';

/// Where `CachedRelayInfoRepo` keeps the answers of relays across restarts,
/// keyed by [RelayInfoRecord.url].
abstract interface class RelayInfoCache {
  /// replaces the record of its url
  Future<void> saveRelayInfo(RelayInfoRecord record);

  Future<RelayInfoRecord?> loadRelayInfo(String url);

  Future<void> removeRelayInfo(String url);

  Future<void> removeAllRelayInfos();
}
