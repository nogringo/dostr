import 'package:ndk_core/domain_layer/entities/relay_connectivity.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'package:ndk_core/shared/helpers/relay_helper.dart';

import '../../entities/relay_info.dart';
import '../../repositories/relay_info_repo.dart';

/// get connectivity status \
/// & update ndk about your application connectivity for faster reconnects
class Connectivy {
  final RelayManager _relayManager;
  final RelayInfoRepo _relayInfoRepo;
  final Map<String, Future<RelayInfo?>> _relayInfoCache = {};

  Connectivy(this._relayManager, this._relayInfoRepo);

  /// streams connectivity status of every connection \
  /// a relay can hold several, so group by [RelayConnectivity.url] if needed
  Stream<List<RelayConnectivity>> get relayConnectivityChanges =>
      _relayManager.relayConnectivityChanges;

  /// NIP-11 info of the relay at [url], fetched once and then cached \
  /// concurrent calls share the request, failures are retried on the next call \
  /// returns null when the relay does not provide it
  Future<RelayInfo?> getRelayInfo(String url) async {
    final key = cleanRelayUrl(url) ?? url;
    final pending = _relayInfoCache[key];
    if (pending != null) return pending;
    final fetch = _relayInfoCache[key] = _relayInfoRepo.getRelayInfo(key);
    RelayInfo? info;
    try {
      info = await fetch;
      return info;
    } finally {
      if (info == null) _relayInfoCache.remove(key);
    }
  }

  /// forces all relays to reconnect \
  /// use this for faster reconnects based on your application/os connectivity \
  Future<void> tryReconnect() => _relayManager.reconnectClosedConnections();
}
