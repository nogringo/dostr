part of 'url_set.dart';

/// Watches one list of [pubkey], where a [UrlListFn] looks it up once.
///
/// Each [UrlListFound] it emits is a newer version of the list and replaces
/// the one before. A [UrlListNotFound] or [UrlListUnavailable] ends the
/// lookup, and comes only when no version was found. A stream that ends
/// without emitting counts as unavailable. Report a list that cannot be read
/// as [UrlListUnavailable]: an error ends the whole [watchUrlSet] with it.
///
/// [outboxRelays] gives the NIP-65 write relays of [pubkey] once their lookup
/// ended, when [UrlListKind.onOutbox]: empty when [pubkey] has no NIP-65 or
/// it is unavailable. [watchUrlSet] calls this before they are known, so a
/// lookup that finds them itself starts right away. Always empty for the
/// NIP-65 kinds.
typedef UrlListWatchFn =
    Stream<UrlListLookup> Function(
      String pubkey,
      UrlListKind kind,
      Future<List<String>> outboxRelays,
    );

/// What a [UrlSet] resolves to so far, as [watchUrlSet] gives it.
final class UrlSetSnapshot {
  /// URLs of the lists known so far, in tree order, not deduplicated.
  ///
  /// A later snapshot may drop some: a newer version of a list replaces the
  /// one before, a fallback moves past a set whose list turns out empty, and
  /// [UrlSet.first] keeps the first URLs of the lists known at the time.
  final List<String> urls;

  /// Why each unavailable lookup the set depends on is.
  final List<String> unavailable;

  /// Whether every lookup the set depends on ended. Only the last snapshot
  /// is.
  final bool done;

  /// Creates a snapshot.
  const UrlSetSnapshot({
    required this.urls,
    this.unavailable = const [],
    required this.done,
  });

  /// [urls], or [unavailable] when there is one. Once [done], it is what
  /// [resolveUrlSet] gives with the lists as they ended.
  UrlResolution get resolution => unavailable.isEmpty
      ? UrlsResolved(urls)
      : UrlsUnavailable(unavailable.join('; '));

  bool _sameAs(UrlSetSnapshot other) =>
      done == other.done &&
      _sameList(urls, other.urls) &&
      _sameList(unavailable, other.unavailable);
}

/// Resolves [set] with [watch] as its lists arrive, where [resolveUrlSet]
/// waits for every one. A snapshot comes on listen, then on each change, and
/// the stream ends after the [UrlSetSnapshot.done] one.
///
/// Each `(pubkey, kind)` pair is watched at most once, and [UrlSet.fallback]
/// watches a set only once the ones before it ended empty. A list published
/// on the owner's outbox (DM, private, Blossom) is watched along with the
/// NIP-65 of the same pubkey, and ends with it: while that one is
/// unavailable, so is the list, which keeps the URLs it found.
///
/// The lookups are cancelled once done, or when the stream is.
Stream<UrlSetSnapshot> watchUrlSet(UrlSet set, UrlListWatchFn watch) {
  late final _UrlSetWatch resolution;
  final snapshots = StreamController<UrlSetSnapshot>(
    onListen: () => resolution.update(),
    onCancel: () => resolution.cancel(),
  );
  resolution = _UrlSetWatch(set, watch, snapshots);
  return snapshots.stream;
}

class _UrlSetWatch {
  final UrlSet _set;
  final UrlListWatchFn _watch;
  final StreamController<UrlSetSnapshot> _snapshots;
  final Map<String, _ListWatch> _lists = {};
  UrlSetSnapshot? _last;
  bool _updating = false;
  bool _stale = false;
  bool _ended = false;

  _UrlSetWatch(this._set, this._watch, this._snapshots);

  void update() {
    if (_ended) return;
    // a lookup may answer while the tree is walked
    if (_updating) {
      _stale = true;
      return;
    }
    _updating = true;
    final UrlSetSnapshot snapshot;
    try {
      snapshot = _settle();
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
      return;
    } finally {
      _updating = false;
    }
    if (_ended) return;
    if (!(_last?._sameAs(snapshot) ?? false)) {
      _last = snapshot;
      _snapshots.add(snapshot);
    }
    if (snapshot.done) {
      unawaited(cancel());
      unawaited(_snapshots.close());
    }
  }

  Future<void> cancel() async {
    _ended = true;
    await Future.wait([
      for (final list in _lists.values) ?list.subscription?.cancel(),
    ]);
  }

  UrlSetSnapshot _settle() {
    UrlSetSnapshot snapshot;
    do {
      _stale = false;
      snapshot = _evaluate(_set);
    } while (_stale && !_ended);
    return snapshot;
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_ended) return;
    _snapshots.addError(error, stackTrace);
    unawaited(cancel());
    unawaited(_snapshots.close());
  }

  UrlSetSnapshot _evaluate(UrlSet set) => switch (set) {
    ExplicitUrls(:final urls) => UrlSetSnapshot(urls: urls, done: true),
    _ListUrls(:final pubkey, :final _kind) => _evaluateList(pubkey, _kind),
    UnionUrls(:final sets) => _union([for (final s in sets) _evaluate(s)]),
    FallbackUrls(:final sets) => _fallback(sets),
    FirstUrls(count: 0) => const UrlSetSnapshot(urls: [], done: true),
    FirstUrls(:final count, :final set) => _first(count, _evaluate(set)),
  };

  UrlSetSnapshot _first(int count, UrlSetSnapshot set) => UrlSetSnapshot(
    urls: set.urls.take(count).toList(),
    unavailable: set.unavailable,
    done: set.done,
  );

  UrlSetSnapshot _union(List<UrlSetSnapshot> parts) => UrlSetSnapshot(
    urls: [for (final part in parts) ...part.urls],
    unavailable: [for (final part in parts) ...part.unavailable],
    done: parts.every((part) => part.done),
  );

  UrlSetSnapshot _fallback(List<UrlSet> sets) {
    for (final set in sets) {
      final snapshot = _evaluate(set);
      if (!snapshot.done ||
          snapshot.urls.isNotEmpty ||
          snapshot.unavailable.isNotEmpty) {
        return snapshot;
      }
    }
    return const UrlSetSnapshot(urls: [], done: true);
  }

  UrlSetSnapshot _evaluateList(String pubkey, UrlListKind kind) {
    final outbox = kind.onOutbox ? _list(pubkey, UrlListKind.outbox) : null;
    final list = _list(pubkey, kind);
    final latest = list.latest;
    final urls = latest is UrlListFound ? latest.urls : const <String>[];
    if (!list.ended || !(outbox?.ended ?? true)) {
      return UrlSetSnapshot(urls: urls, done: false);
    }
    if (outbox?.latest case UrlListUnavailable(:final reason)) {
      return UrlSetSnapshot(
        urls: urls,
        unavailable: [
          _unavailableReason(pubkey, kind, 'NIP-65 ${reason ?? 'unavailable'}'),
        ],
        done: true,
      );
    }
    if (latest case UrlListUnavailable(:final reason)) {
      return UrlSetSnapshot(
        urls: const [],
        unavailable: [_unavailableReason(pubkey, kind, reason)],
        done: true,
      );
    }
    return UrlSetSnapshot(urls: urls, done: true);
  }

  _ListWatch _list(String pubkey, UrlListKind kind) {
    final key = '${kind.name}|$pubkey';
    if (_lists[key] case final list?) return list;

    final outbox = kind.onOutbox ? _list(pubkey, UrlListKind.outbox) : null;
    final list = _lists[key] = _ListWatch();
    final outboxRelays = outbox == null
        ? Future.value(const <String>[])
        : outbox.result.then(
            (lookup) => lookup is UrlListFound ? lookup.urls : const <String>[],
          );
    list.subscription = _watch(pubkey, kind, outboxRelays).listen(
      (lookup) {
        list.answer(lookup);
        update();
      },
      onError: _fail,
      onDone: () {
        list.end();
        update();
      },
    );
    return list;
  }
}

class _ListWatch {
  UrlListLookup? latest;
  StreamSubscription<UrlListLookup>? subscription;
  final _result = Completer<UrlListLookup>();

  /// How the lookup ended.
  Future<UrlListLookup> get result => _result.future;

  bool get ended => _result.isCompleted;

  void answer(UrlListLookup lookup) {
    if (ended) return;
    latest = lookup;
    if (lookup is! UrlListFound) end();
  }

  void end() {
    if (!ended) _result.complete(latest ??= const UrlListLookup.unavailable());
  }
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
