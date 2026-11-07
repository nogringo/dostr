import 'package:ndk_nip01/ndk_nip01.dart';

/// Where [Lists] reads the list and set events it knows and keeps the ones it
/// loads or publishes. NDK's `CacheManager` implements it.
abstract interface class Nip51ListCache {
  /// Visible events only: of a replaceable or addressable event, just the
  /// version that supersedes the others.
  Future<List<Nip01Event>> loadEvents({
    List<String>? pubKeys,
    List<int>? kinds,
  });

  Future<void> saveEvent(Nip01Event event);

  Future<void> removeEvent(String id);
}
