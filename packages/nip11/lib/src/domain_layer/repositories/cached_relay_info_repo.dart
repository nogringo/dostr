import '../entities/relay_info.dart';
import 'relay_info_repo.dart';

/// [RelayInfoRepo] that fetches the info of a relay once and then serves it
/// from memory, a relay that answered without one included. Concurrent calls
/// share the request, and a fetch that throws is asked again on the next
/// call, or once [failureMaxAge] passes. Urls are keys as given, so normalize
/// them first.
class CachedRelayInfoRepo implements RelayInfoRepo {
  final RelayInfoRepo _repo;

  /// how long an answer is served once it arrived; null keeps it for the life
  /// of this cache
  final Duration? maxAge;

  /// how long a fetch that throws keeps throwing without asking again, so a
  /// relay that is down or rate limits is not asked on every call; null asks
  /// again on the next call
  final Duration? failureMaxAge;

  final Map<String, _Entry> _cache = {};

  CachedRelayInfoRepo(this._repo, {this.maxAge, this.failureMaxAge});

  @override
  Future<RelayInfo?> getRelayInfo(String url) async {
    final cached = _cache[url];
    if (cached != null && !cached.isExpired) return cached.info;
    _cache.removeWhere((_, entry) => entry.isExpired);
    final entry = _cache[url] = _Entry(_repo.getRelayInfo(url));
    try {
      final info = await entry.info;
      entry.expireAfter(maxAge);
      return info;
    } catch (_) {
      entry.expireAfter(failureMaxAge ?? Duration.zero);
      rethrow;
    }
  }

  /// forgets [url], so the next call fetches it again
  void evict(String url) => _cache.remove(url);

  /// forgets every relay
  void clear() => _cache.clear();
}

class _Entry {
  final Future<RelayInfo?> info;

  /// null while the fetch runs, or when the answer never expires
  DateTime? _expiresAt;

  _Entry(this.info);

  void expireAfter(Duration? age) {
    if (age != null) _expiresAt = DateTime.now().add(age);
  }

  bool get isExpired => switch (_expiresAt) {
    final expiresAt? => !DateTime.now().isBefore(expiresAt),
    null => false,
  };
}
