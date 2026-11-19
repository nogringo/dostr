/// NIP-05 identifiers for Nostr.
///
/// ```dart
/// final nip05 = Nip05Resolver(cache: cache);
/// final result = await nip05.resolve('bob@example.com');
/// ```
library;

export 'package:dostr_relay_url/dostr_relay_url.dart';

export 'src/config/nip_05_defaults.dart';
export 'src/data_layer/repositories/http_nip_05_repository.dart';
export 'src/domain_layer/entities/nip_05.dart';
export 'src/domain_layer/entities/nip_05_record.dart';
export 'src/domain_layer/entities/nip_05_results.dart';
export 'src/domain_layer/repositories/nip_05_cache.dart';
export 'src/domain_layer/repositories/nip_05_repository.dart';
export 'src/domain_layer/usecases/nip_05_resolver.dart';
