import '../entities/relay_info.dart';
import 'relay_info_repo.dart';

/// [RelayInfoRepo] that fetches the info of a relay once and then serves it
/// from memory. Concurrent calls share the request, and a fetch that fails
/// or returns null is retried on the next call. Urls are keys as given, so
/// normalize them first.
class CachedRelayInfoRepo implements RelayInfoRepo {
  final RelayInfoRepo _repo;
  final Map<String, Future<RelayInfo?>> _cache = {};

  CachedRelayInfoRepo(this._repo);

  @override
  Future<RelayInfo?> getRelayInfo(String url) async {
    final pending = _cache[url];
    if (pending != null) return pending;
    final fetch = _cache[url] = _repo.getRelayInfo(url);
    RelayInfo? info;
    try {
      info = await fetch;
      return info;
    } finally {
      if (info == null) _cache.remove(url);
    }
  }
}
