/// NIP-11 relay information for NDK.
///
/// ```dart
/// final repo = HttpRelayInfoRepo(http.Client());
/// final info = await repo.getRelayInfo('wss://relay.example.com');
/// print(info?.supportsNip('50'));
/// ```
library;

export 'src/data_layer/repositories/http_relay_info_repo.dart';
export 'src/domain_layer/entities/relay_info.dart';
export 'src/domain_layer/entities/relay_info_record.dart';
export 'src/domain_layer/repositories/cached_relay_info_repo.dart';
export 'src/domain_layer/repositories/relay_info_cache.dart';
export 'src/domain_layer/repositories/relay_info_repo.dart';
