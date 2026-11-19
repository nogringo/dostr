import 'dart:async';

import 'package:http/http.dart' as http;

import '../../config/nip_05_defaults.dart';
import '../../data_layer/repositories/http_nip_05_repository.dart';
import '../entities/nip_05.dart';
import '../entities/nip_05_record.dart';
import '../entities/nip_05_results.dart';
import '../repositories/nip_05_cache.dart';
import '../repositories/nip_05_repository.dart';

/// Resolves and verifies NIP-05 identifiers.
///
/// [resolve] and [check] take an `abortTrigger`. Once it completes, with a
/// value or an error, that call ends with a `RequestAbortedException` (from
/// `package:http`) as [abortPending] would end it, and the others go on.
class Nip05Resolver {
  final Nip05Cache _cache;
  final Nip05Repository _nip05Repository;

  /// the client this instance made, which [close] closes
  final http.Client? _ownedClient;

  // Keep request deduplication local to this instance. Different instances
  // may use different repositories and caches for the same NIP-05.
  final Map<String, _Flight> _flights = {};

  /// how many times [abortPending] ran
  int _aborts = 0;

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
    );
  }

  Nip05Resolver._(this._cache, this._nip05Repository, this._ownedClient);

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
  /// it is the caller's to close. This instance is unusable afterwards.
  void close() {
    abortPending();
    _ownedClient?.close();
  }

  /// Whether [nip05] points to [pubkey], in hex, resolved as [resolve] does.
  Future<Nip05CheckResult> check({
    required String nip05,
    required String pubkey,
    Future<void>? abortTrigger,
  }) async {
    final result = await resolve(nip05, abortTrigger: abortTrigger);
    return switch (result) {
      Nip05Found(:final data) when data.pubkey == pubkey.toLowerCase() =>
        Nip05Verified(data),
      Nip05Found(:final data) => Nip05Mismatch(data),
      Nip05NotFound notFound => notFound,
      Nip05ResolveError error => error,
    };
  }

  /// The pubkey and relays [nip05] (e.g. "username@example.com") points to.
  ///
  /// A [Nip05Found] is remembered for [nip05ValidDuration], a [Nip05NotFound]
  /// for [nip05NotFoundDuration], and a [Nip05ResolveError] not at all.
  /// Concurrent calls for one identifier share one request. An error of the
  /// cache is not caught.
  Future<Nip05ResolveResult> resolve(
    String nip05, {
    Future<void>? abortTrigger,
  }) async {
    final identifier = Nip05.canonicalIdentifier(nip05);
    if (identifier == null) {
      return const Nip05NotFound();
    }

    final abortsAtStart = _aborts;
    var triggered = false;
    unawaited(
      abortTrigger?.then(
        (_) => triggered = true,
        onError: (Object _) => triggered = true,
      ),
    );

    final cached = _fresh(await _cache.loadNip05(identifier));
    if (triggered || _aborts != abortsAtStart) {
      throw http.RequestAbortedException();
    }
    if (cached != null) {
      return cached;
    }

    final flight = _flights[identifier] ??= _start(identifier);
    return flight.join(abortTrigger);
  }

  Nip05ResolveResult? _fresh(Nip05Record? record) {
    if (record == null) {
      return null;
    }
    final age = DateTime.now().difference(record.fetchedAt);
    final nip05 = record.nip05;
    if (nip05 == null) {
      return age < nip05NotFoundDuration ? const Nip05NotFound() : null;
    }
    return age < nip05ValidDuration ? Nip05Found(nip05) : null;
  }

  _Flight _start(String identifier) {
    late final _Flight flight;
    void forget() {
      if (identical(_flights[identifier], flight)) {
        _flights.remove(identifier);
      }
    }

    flight = _Flight(forget);
    flight.settle(_fetch(identifier, flight.abortTrigger).whenComplete(forget));
    return flight;
  }

  Future<Nip05ResolveResult> _fetch(
    String identifier,
    Future<void> abortTrigger,
  ) async {
    final Nip05? nip05;
    try {
      nip05 = await _nip05Repository.fetchNip05(
        identifier,
        abortTrigger: abortTrigger,
      );
    } on FormatException catch (e) {
      return Nip05ResolveInvalidResponse(e);
    } on Exception catch (e) {
      return Nip05ResolveNetworkError(e);
    }
    await _cache.saveNip05(
      Nip05Record(
        identifier: identifier,
        nip05: nip05,
        fetchedAt: DateTime.now(),
      ),
    );
    return nip05 == null ? const Nip05NotFound() : Nip05Found(nip05);
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
