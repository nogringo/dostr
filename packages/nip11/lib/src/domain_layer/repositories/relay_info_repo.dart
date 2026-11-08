import '../entities/relay_info.dart';

/// repository to fetch NIP-11 relay information
abstract class RelayInfoRepo {
  /// network request to get the [RelayInfo] of the relay at [url]; returns
  /// null when the relay answers without one, and throws when it could not be
  /// reached, so the caller can ask again later
  Future<RelayInfo?> getRelayInfo(String url);
}
