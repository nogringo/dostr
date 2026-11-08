import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip11/ndk_nip11.dart';

const _relayInfoMaxAge = Duration(hours: 1);
const _relayInfoFailureMaxAge = Duration(minutes: 1);

@Deprecated('Use Connectivity')
typedef Connectivy = Connectivity;

/// get connectivity status \
/// & update ndk about your application connectivity for faster reconnects
class Connectivity {
  final RelayManager _relayManager;
  final CachedRelayInfoRepo _relayInfoRepo;

  /// [cache] keeps the NIP-11 documents across restarts, ndk gives it
  /// `NdkConfig.cache`
  Connectivity(
    this._relayManager,
    RelayInfoRepo relayInfoRepo, {
    RelayInfoCache? cache,
  }) : _relayInfoRepo = CachedRelayInfoRepo(
         relayInfoRepo,
         cache: cache,
         maxAge: _relayInfoMaxAge,
         failureMaxAge: _relayInfoFailureMaxAge,
       );

  /// streams connectivity status of every connection \
  /// a relay can hold several, so group by [RelayConnectivity.url] if needed
  Stream<List<RelayConnectivity>> get relayConnectivityChanges =>
      _relayManager.relayConnectivityChanges;

  /// NIP-11 info of the relay at [url], fetched once and then cached for an hour, across restarts in `NdkConfig.cache` \
  /// concurrent calls share the request, a relay that could not be reached is asked again after a minute \
  /// and keeps its last document meanwhile \
  /// returns null when the relay serves no document, or could not be reached and never answered \
  /// ndk also asks it each time it opens a socket, for `limitation.max_subscriptions`
  Future<RelayInfo?> getRelayInfo(String url) async {
    try {
      return await _relayInfoRepo.getRelayInfo(cleanRelayUrl(url) ?? url);
    } on Exception {
      return null;
    }
  }

  /// forces all relays to reconnect \
  /// use this for faster reconnects based on your application/os connectivity \
  Future<void> tryReconnect() => _relayManager.reconnectClosedConnections();
}
