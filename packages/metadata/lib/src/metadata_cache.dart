import 'package:ndk_nip01/ndk_nip01.dart';

import 'metadata.dart';

/// Where [Metadatas] reads the metadata it knows and keeps the ones it loads
/// or publishes. NDK's `CacheManager` implements it.
abstract interface class MetadataCache {
  /// The newest cached metadata (kind 0) of [pubKey], or null.
  Future<Metadata?> loadMetadata(String pubKey);

  Future<void> saveEvent(Nip01Event event);
}
