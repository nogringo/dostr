import 'dart:async';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;

import 'hex_pubkey.dart';
import 'http_nip_05_repository.dart';
import 'nip_05.dart';
import 'nip_05_cache.dart';
import 'nip_05_defaults.dart';
import 'nip_05_record.dart';
import 'nip_05_repository.dart';
import 'nip_05_results.dart';

/// Resolves and verifies NIP-05 identifiers.
///
/// [resolve] and [check] take an `abortTrigger`. Once it completes, with a
/// value or an error, that call ends with a `RequestAbortedException` (from
/// `package:http`) as [abortPending] would end it, and the others go on.
class Nip05Resolver {
  final Nip05Cache _cache;
  final Nip05Repository _nip05Repository;

  /// how long [resolve] remembers an identifier it found
  final Duration validDuration;

  /// how long [resolve] remembers an identifier that does not exist
  final Duration notFoundDuration;

  /// how long [resolve] gives a [Nip05ResolveNetworkError] again, without a
  /// request, for every identifier of the domain that could not be reached
  final Duration networkErrorDuration;

  /// the client this instance made, which [close] closes
  final http.Client? _ownedClient;

  // Keep request deduplication local to this instance. Different instances
  // may use different repositories and caches for the same NIP-05.
  final Map<String, _Flight> _flights = {};

  final Map<String, ({Nip05ResolveNetworkError error, DateTime until})>
  _failedDomains = {};

  /// how many times [abortPending] ran
  int _aborts = 0;

  bool _closed = false;

  /// [cache] keeps the resolved identifiers, in memory for the life of this
  /// resolver when null.
  ///
  /// It fetches them over HTTP with [httpClient], or with a client of its own
  /// that [close] closes. [nip05Repository] replaces that HTTP layer, and the
  /// two cannot be given together.
  factory Nip05Resolver({
    Nip05Cache? cache,
    http.Client? httpClient,
    Nip05Repository? nip05Repository,
    Duration validDuration = nip05ValidDuration,
    Duration notFoundDuration = nip05NotFoundDuration,
    Duration networkErrorDuration = nip05NetworkErrorDuration,
  }) {
    if (httpClient != null && nip05Repository != null) {
      throw ArgumentError(
        'Nip05Resolver takes an httpClient or a nip05Repository, not both',
      );
    }
    final ownedClient = httpClient == null && nip05Repository == null
        ? http.Client()
        : null;
    return Nip05Resolver._(
      cache ?? _MemoryNip05Cache(),
      nip05Repository ??
          HttpNip05Repository(client: httpClient ?? ownedClient!),
      ownedClient,
      validDuration: validDuration,
      notFoundDuration: notFoundDuration,
      networkErrorDuration: networkErrorDuration,
    );
  }

  Nip05Resolver._(
    this._cache,
    this._nip05Repository,
    this._ownedClient, {
    required this.validDuration,
    required this.notFoundDuration,
    required this.networkErrorDuration,
  });

  /// Ends the calls in flight with a `RequestAbortedException` (from
  /// `package:http`), including those still reading the cache: none sends a
  /// request afterwards. This instance stays usable.
  void abortPending() {
    _aborts++;
    for (final flight in _flights.values.toList()) {
      flight.abort();
    }
  }

  /// Ends the calls in flight, as [abortPending] does, and closes the HTTP
  /// client this instance made. A client given to the constructor stays open:
  /// it is the caller's to close. [resolve] and [check] throw a [StateError]
  /// afterwards.
  void close() {
    _closed = true;
    abortPending();
    _ownedClient?.close();
  }

  /// Whether [nip05] points to [pubkey], in hex, resolved as [resolve] does.
  ///
  /// Throws an [ArgumentError] when [pubkey] is not in hex, such as an npub.
  Future<Nip05CheckResult> check({
    required String nip05,
    required String pubkey,
    bool refresh = false,
    Future<void>? abortTrigger,
  }) async {
    if (!hexPubkey.hasMatch(pubkey)) {
      throw ArgumentError.value(pubkey, 'pubkey', 'not a hex pubkey');
    }
    final result = await resolve(
      nip05,
      refresh: refresh,
      abortTrigger: abortTrigger,
    );
    return switch (result) {
      Nip05Found(:final data, :final fetchedAt)
          when data.pubkey == pubkey.toLowerCase() =>
        Nip05Verified(data, fetchedAt: fetchedAt),
      Nip05Found(:final data, :final fetchedAt) => Nip05Mismatch(
        data,
        fetchedAt: fetchedAt,
      ),
      Nip05NotFound notFound => notFound,
      Nip05ResolveError error => error,
    };
  }

  /// The pubkey and relays [nip05] (e.g. "username@example.com") points to.
  ///
  /// A [Nip05Found] is remembered for [validDuration] and a [Nip05NotFound]
  /// for [notFoundDuration], in the cache. A [Nip05ResolveNetworkError] is
  /// given again for [networkErrorDuration] to every identifier of its domain,
  /// and a [Nip05ResolveInvalidResponse] is not remembered. [refresh] asks the
  /// domain whatever was remembered, such as when the user fixed their
  /// nostr.json.
  ///
  /// Concurrent calls for one identifier share one request. An error of the
  /// cache is not caught when it reads, and ignored when it saves. Throws a
  /// [StateError] once [close] ran.
  Future<Nip05ResolveResult> resolve(
    String nip05, {
    bool refresh = false,
    Future<void>? abortTrigger,
  }) async {
    if (_closed) {
      throw StateError('the Nip05Resolver was closed');
    }
    final identifier = Nip05.canonicalIdentifier(nip05);
    if (identifier == null) {
      return const Nip05NotFound();
    }

    if (!refresh) {
      if (await _cached(identifier, abortTrigger) case final cached?) {
        return cached;
      }
    }

    final domain = identifier.split('@').last;
    if (!refresh && !_flights.containsKey(identifier)) {
      if (_recentFailure(domain) case final error?) {
        return error;
      }
    }
    final flight = _flights[identifier] ??= _start(identifier, domain);
    return flight.join(abortTrigger);
  }

  /// what the cache holds for [identifier] while it is fresh. Throws a
  /// `RequestAbortedException` when [abortTrigger] or [abortPending] ran
  /// during the read
  Future<Nip05ResolveResult?> _cached(
    String identifier,
    Future<void>? abortTrigger,
  ) async {
    final abortsAtStart = _aborts;
    var triggered = false;
    unawaited(
      abortTrigger?.then(
        (_) => triggered = true,
        onError: (Object _) => triggered = true,
      ),
    );

    final record = await _cache.loadNip05(identifier);
    if (triggered || _aborts != abortsAtStart) {
      throw http.RequestAbortedException();
    }
    if (record == null) {
      return null;
    }
    final age = clock.now().difference(record.fetchedAt);
    return switch (record.nip05) {
      null => age < notFoundDuration ? const Nip05NotFound() : null,
      final nip05 =>
        age < validDuration
            ? Nip05Found(nip05, fetchedAt: record.fetchedAt)
            : null,
    };
  }

  Nip05ResolveNetworkError? _recentFailure(String domain) {
    final failure = _failedDomains[domain];
    if (failure == null) {
      return null;
    }
    if (clock.now().isBefore(failure.until)) {
      return failure.error;
    }
    _failedDomains.remove(domain);
    return null;
  }

  void _rememberFailure(String domain, Nip05ResolveNetworkError error) {
    final now = clock.now();
    _failedDomains
      ..removeWhere((_, failure) => !now.isBefore(failure.until))
      ..[domain] = (error: error, until: now.add(networkErrorDuration));
  }

  _Flight _start(String identifier, String domain) {
    late final _Flight flight;
    void forget() {
      if (identical(_flights[identifier], flight)) {
        _flights.remove(identifier);
      }
    }

    flight = _Flight(forget);
    flight.settle(_fetch(identifier, domain, flight).whenComplete(forget));
    return flight;
  }

  Future<Nip05ResolveResult> _fetch(
    String identifier,
    String domain,
    _Flight flight,
  ) async {
    final Nip05? nip05;
    try {
      nip05 = await _nip05Repository.fetchNip05(
        identifier,
        abortTrigger: flight.abortTrigger,
      );
    } on FormatException catch (e) {
      _failedDomains.remove(domain);
      return Nip05ResolveInvalidResponse(e);
    } on Exception catch (e) {
      final error = Nip05ResolveNetworkError(e);
      if (!flight.isAborted) {
        _rememberFailure(domain, error);
      }
      return error;
    }
    _failedDomains.remove(domain);

    final record = Nip05Record(
      identifier: identifier,
      nip05: nip05,
      fetchedAt: clock.now(),
    );
    try {
      await _cache.saveNip05(record);
    } catch (_) {
      // a cache that cannot save costs a request later, not this answer
    }
    return nip05 == null
        ? const Nip05NotFound()
        : Nip05Found(nip05, fetchedAt: record.fetchedAt);
  }
}

/// One request for an identifier, shared by the calls waiting on it
class _Flight {
  final _abort = Completer<void>();
  final _waiters = <Completer<Nip05ResolveResult>>{};

  /// runs once the request is aborted, so no new call joins it
  final void Function() _onAbort;

  _Flight(this._onAbort);

  /// completes once no call waits on the request any more
  Future<void> get abortTrigger => _abort.future;

  bool get isAborted => _abort.isCompleted;

  /// what the request gives, or a `RequestAbortedException` once [trigger]
  /// completes
  Future<Nip05ResolveResult> join(Future<void>? trigger) {
    final waiter = Completer<Nip05ResolveResult>();
    _waiters.add(waiter);
    unawaited(
      trigger?.then(
        (_) => _leave(waiter),
        onError: (Object _) => _leave(waiter),
      ),
    );
    return waiter.future;
  }

  void _leave(Completer<Nip05ResolveResult> waiter) {
    if (!_waiters.remove(waiter)) return;
    waiter.completeError(http.RequestAbortedException());
    if (_waiters.isEmpty) abort();
  }

  /// ends every call still waiting with a `RequestAbortedException`, and the
  /// request
  void abort() {
    for (final waiter in _drain()) {
      waiter.completeError(http.RequestAbortedException());
    }
    if (_abort.isCompleted) return;
    _abort.complete();
    _onAbort();
  }

  void settle(Future<Nip05ResolveResult> result) {
    unawaited(
      result.then(
        (value) {
          for (final waiter in _drain()) {
            waiter.complete(value);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          for (final waiter in _drain()) {
            waiter.completeError(error, stackTrace);
          }
        },
      ),
    );
  }

  List<Completer<Nip05ResolveResult>> _drain() {
    final waiters = _waiters.toList();
    _waiters.clear();
    return waiters;
  }
}

class _MemoryNip05Cache implements Nip05Cache {
  final Map<String, Nip05Record> _records = {};

  @override
  Future<void> saveNip05(Nip05Record record) async {
    _records[record.identifier] = record;
  }

  @override
  Future<Nip05Record?> loadNip05(String identifier) async =>
      _records[identifier];
}
