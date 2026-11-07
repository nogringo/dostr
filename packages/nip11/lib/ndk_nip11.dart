/// NIP-11 relay information for NDK.
///
/// ```dart
/// final connectivity = Connectivy(
///   relayManager,
///   RelayInfoHttpRepoImpl(httpDS: NdkHttp(http.Client())),
/// );
/// final info = await connectivity.getRelayInfo('wss://relay.example.com');
/// print(info?.supportsNip('50'));
/// ```
library;

export 'src/data_layer/repositories/relay_info_http_impl.dart';
export 'src/domain_layer/entities/relay_info.dart';
export 'src/domain_layer/repositories/relay_info_repo.dart';
export 'src/domain_layer/usecases/connectivity.dart';
