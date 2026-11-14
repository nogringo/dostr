/// NIP-05 identifiers for Nostr.
///
/// ```dart
/// final nip05 = Nip05Resolver(
///   cache: cache,
///   nip05Repository: HttpNip05Repository(client: http.Client()),
/// );
/// final result = await nip05.resolve('bob@example.com');
/// ```
library;

export 'src/config/nip_05_defaults.dart';
export 'src/data_layer/repositories/http_nip_05_repository.dart';
export 'src/domain_layer/entities/nip_05.dart';
export 'src/domain_layer/entities/nip_05_resolve_result.dart';
export 'src/domain_layer/repositories/nip_05_cache.dart';
export 'src/domain_layer/repositories/nip_05_repository.dart';
export 'src/domain_layer/usecases/nip_05_resolver.dart';
