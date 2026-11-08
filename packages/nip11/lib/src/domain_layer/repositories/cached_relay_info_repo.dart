import 'dart:math';

import 'package:clock/clock.dart';

import '../entities/relay_info.dart';
import '../entities/relay_info_record.dart';
import 'relay_info_cache.dart';
import 'relay_info_repo.dart';

/// [RelayInfoRepo] that fetches the info of a relay once and then serves it
/// from memory, a relay that answered without one included, and from [cache]
/// after a restart. Concurrent calls share the request. A fetch that throws
/// serves the last answer of the relay, or throws when it never answered, and
/// is asked again on the next call, or once [failureMaxAge] passes. Urls are
/// keys as given, so normalize them first.
class CachedRelayInfoRepo implements RelayInfoRepo {
  final RelayInfoRepo _repo;

  /// keeps every answer, read on the first call for a relay. A read that
  /// throws fetches the relay, and a write that throws keeps the answer in
  /// memory only
  final RelayInfoCache? cache;

  /// how long an answer is served before it is fetched again, aged by the
  /// system clock once read from [cache]; null keeps it until evicted
  final Duration? maxAge;

  /// how long a fetch that throws is not asked again, so a relay that is down
  /// or rate limits is not asked on every call; null asks again on the next
  /// call
  final Duration? failureMaxAge;

  final Stopwatch _clock;

  final Map<String, _Entry> _entries = {};

  var _sweepAt = _minSweep;

  static const _minSweep = 64;

  /// [stopwatch] measures the age of answers, a new one by default, which a
  /// change of the system clock does not move. A test can pass
  /// `clock.stopwatch()` of `package:clock` to drive it with `fakeAsync`,
  /// which also drives the `clock.now()` that dates the records of [cache].
  CachedRelayInfoRepo(
    this._repo, {
    this.cache,
    this.maxAge,
    this.failureMaxAge,
    Stopwatch? stopwatch,
  }) : _clock = (stopwatch ?? Stopwatch())..start();

  @override
  Future<RelayInfo?> getRelayInfo(String url) {
    final cached = _entries[url];
    if (cached != null && !cached.isExpiredAt(_clock.elapsed)) {
      return cached.info;
    }
    _sweep();
    final entry = _entries[url] = _Entry(cached?.answer);
    return entry.info = cached == null && cache != null
        ? _load(url, entry)
        : _fetch(url, entry);
  }

  Future<RelayInfo?> _load(String url, _Entry entry) async {
    final RelayInfoRecord? record;
    try {
      record = await cache!.loadRelayInfo(url);
    } catch (_) {
      return _fetch(url, entry);
    }
    if (record == null) return _fetch(url, entry);
    entry.answer = (info: record.info);
    final remaining = _remaining(record.fetchedAt);
    if (remaining != null && remaining <= Duration.zero) {
      return _fetch(url, entry);
    }
    entry.expiresAt = _after(remaining);
    return record.info;
  }

  /// what is left of [maxAge] for an answer of [fetchedAt]; one dated after
  /// now, by a clock set back, counts as fresh
  Duration? _remaining(DateTime fetchedAt) {
    final maxAge = this.maxAge;
    if (maxAge == null) return null;
    final age = clock.now().difference(fetchedAt);
    return age.isNegative ? maxAge : maxAge - age;
  }

  Future<RelayInfo?> _fetch(String url, _Entry entry) async {
    final RelayInfo? info;
    try {
      info = await _repo.getRelayInfo(url);
    } catch (_) {
      entry.expiresAt = _after(failureMaxAge ?? Duration.zero);
      if (entry.answer case final answer?) return answer.info;
      rethrow;
    }
    entry
      ..answer = (info: info)
      ..expiresAt = _after(maxAge);
    // a fetch evicted while it ran must not bring its relay back
    if (cache case final cache? when identical(_entries[url], entry)) {
      try {
        await cache.saveRelayInfo(
          RelayInfoRecord(url: url, info: info, fetchedAt: clock.now()),
        );
      } catch (_) {}
    }
    return info;
  }

  Duration? _after(Duration? age) => age == null ? null : _clock.elapsed + age;

  /// once the cache doubled since the last sweep, so a miss costs O(1)
  /// amortized. An answer stays, to serve when its relay cannot be reached
  void _sweep() {
    if (_entries.length < _sweepAt) return;
    final now = _clock.elapsed;
    _entries.removeWhere(
      (_, entry) => entry.answer == null && entry.isExpiredAt(now),
    );
    _sweepAt = max(_minSweep, _entries.length * 2);
  }

  /// forgets [url], in [cache] too, so the next call fetches it again
  Future<void> evict(String url) async {
    _entries.remove(url);
    await cache?.removeRelayInfo(url);
  }

  /// forgets every relay, in [cache] too
  Future<void> clear() async {
    _entries.clear();
    await cache?.removeAllRelayInfos();
  }
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
