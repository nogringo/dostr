import '../entities/relay_info.dart';
import 'relay_info_repo.dart';

/// [RelayInfoRepo] that fetches the info of a relay once and then serves it
/// from memory, a relay that answered without one included. Concurrent calls
/// share the request, and a fetch that throws is retried on the next call.
/// Urls are keys as given, so normalize them first.
class CachedRelayInfoRepo implements RelayInfoRepo {
  final RelayInfoRepo _repo;

  /// how long an answer is served once it arrived; null keeps it for the life
  /// of this cache
  final Duration? maxAge;

  final Map<String, _Entry> _cache = {};

  CachedRelayInfoRepo(this._repo, {this.maxAge});

  @override
  Future<RelayInfo?> getRelayInfo(String url) async {
    final cached = _cache[url];
    if (cached != null && !cached.isExpired) return cached.info;
    final entry = _cache[url] = _Entry(_repo.getRelayInfo(url));
    try {
      final info = await entry.info;
      if (maxAge case final maxAge?) {
        entry.expiresAt = DateTime.now().add(maxAge);
      }
      return info;
    } catch (_) {
      _cache.remove(url);
      rethrow;
    }
  }
}

class _Entry {
  final Future<RelayInfo?> info;

  /// null while the fetch runs, or when the answer never expires
  DateTime? expiresAt;

  _Entry(this.info);

  bool get isExpired => expiresAt?.isBefore(DateTime.now()) ?? false;
}
