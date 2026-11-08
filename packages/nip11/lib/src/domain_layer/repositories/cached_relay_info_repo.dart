import 'dart:math';

import '../entities/relay_info.dart';
import 'relay_info_repo.dart';

/// [RelayInfoRepo] that fetches the info of a relay once and then serves it
/// from memory, a relay that answered without one included. Concurrent calls
/// share the request. A fetch that throws serves the last answer of the relay,
/// or throws when it never answered, and is asked again on the next call, or
/// once [failureMaxAge] passes. Urls are keys as given, so normalize them
/// first.
class CachedRelayInfoRepo implements RelayInfoRepo {
  final RelayInfoRepo _repo;

  /// how long an answer is served before it is fetched again; null keeps it
  /// for the life of this cache
  final Duration? maxAge;

  /// how long a fetch that throws is not asked again, so a relay that is down
  /// or rate limits is not asked on every call; null asks again on the next
  /// call
  final Duration? failureMaxAge;

  final Stopwatch _clock;

  final Map<String, _Entry> _cache = {};

  var _sweepAt = _minSweep;

  static const _minSweep = 64;

  /// [stopwatch] measures the age of answers, a new one by default, which a
  /// change of the system clock does not move. A test can pass
  /// `clock.stopwatch()` of `package:clock` to drive it with `fakeAsync`.
  CachedRelayInfoRepo(
    this._repo, {
    this.maxAge,
    this.failureMaxAge,
    Stopwatch? stopwatch,
  }) : _clock = (stopwatch ?? Stopwatch())..start();

  @override
  Future<RelayInfo?> getRelayInfo(String url) {
    final cached = _cache[url];
    if (cached != null && !cached.isExpiredAt(_clock.elapsed)) {
      return cached.info;
    }
    _sweep();
    final entry = _cache[url] = _Entry(cached?.answer);
    return entry.info = _fetch(url, entry);
  }

  Future<RelayInfo?> _fetch(String url, _Entry entry) async {
    try {
      final info = await _repo.getRelayInfo(url);
      entry
        ..answer = (info: info)
        ..expiresAt = _after(maxAge);
      return info;
    } catch (_) {
      entry.expiresAt = _after(failureMaxAge ?? Duration.zero);
      if (entry.answer case final answer?) return answer.info;
      rethrow;
    }
  }

  Duration? _after(Duration? age) => age == null ? null : _clock.elapsed + age;

  /// once the cache doubled since the last sweep, so a miss costs O(1)
  /// amortized. An answer stays, to serve when its relay cannot be reached
  void _sweep() {
    if (_cache.length < _sweepAt) return;
    final now = _clock.elapsed;
    _cache.removeWhere(
      (_, entry) => entry.answer == null && entry.isExpiredAt(now),
    );
    _sweepAt = max(_minSweep, _cache.length * 2);
  }

  /// forgets [url], so the next call fetches it again
  void evict(String url) => _cache.remove(url);

  /// forgets every relay
  void clear() => _cache.clear();
}

class _Entry {
  /// what the relay last answered, null while it never did
  ({RelayInfo? info})? answer;

  late final Future<RelayInfo?> info;

  /// null while the fetch runs, or when the answer never expires
  Duration? expiresAt;

  _Entry(this.answer);

  bool isExpiredAt(Duration now) => switch (expiresAt) {
    final expiresAt? => now >= expiresAt,
    null => false,
  };
}
