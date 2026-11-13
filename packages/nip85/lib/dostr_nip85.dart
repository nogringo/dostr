/// NIP-85 trusted assertions for Nostr.
///
/// ```dart
/// final ta = TrustedAssertions(query: query, subscribe: subscribe);
/// final metrics = await ta.getUserMetrics(pubkey);
/// ```
library;

export 'src/config/nip85_defaults.dart';
export 'src/domain_layer/entities/nip_85.dart';
export 'src/domain_layer/usecases/ta/trusted_assertions.dart';
