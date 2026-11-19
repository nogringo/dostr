/// NIP-05 identifiers for Nostr.
///
/// ```dart
/// final nip05 = Nip05Resolver(cache: cache);
/// final result = await nip05.resolve('bob@example.com');
/// ```
library;

export 'package:dostr_relay_url/dostr_relay_url.dart';

export 'src/http_nip_05_repository.dart';
export 'src/nip_05.dart';
export 'src/nip_05_cache.dart';
export 'src/nip_05_defaults.dart';
export 'src/nip_05_record.dart';
export 'src/nip_05_repository.dart';
export 'src/nip_05_resolver.dart';
export 'src/nip_05_results.dart';
