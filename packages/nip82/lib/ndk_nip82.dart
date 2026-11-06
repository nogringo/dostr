/// NIP-82 software applications for NDK.
///
/// ```dart
/// final software = Software(query: query, subscribe: subscribe);
/// final releases = await software.getReleases(app: app);
/// ```
library;

export 'src/domain_layer/entities/software.dart';
export 'src/domain_layer/usecases/software/software.dart';
