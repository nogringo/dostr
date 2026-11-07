/// NIP-11 relay information for NDK.
///
/// ```dart
/// final repo = RelayInfoHttpRepoImpl(httpDS: NdkHttp(http.Client()));
/// final info = await repo.getRelayInfo('wss://relay.example.com');
/// print(info?.supportsNip('50'));
/// ```
library;

export 'src/data_layer/repositories/relay_info_http_impl.dart';
export 'src/domain_layer/entities/relay_info.dart';
export 'src/domain_layer/repositories/cached_relay_info_repo.dart';
export 'src/domain_layer/repositories/relay_info_repo.dart';
