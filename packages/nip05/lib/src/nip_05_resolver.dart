import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;

import 'hex_pubkey.dart';
import 'http_nip_05_repository.dart';
import 'memory_nip_05_cache.dart';
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

  /// how long [resolve] gives a [Nip05ResolveInvalidResponse] again, without a
  /// request, for the identifier it came for
  final Duration invalidResponseDuration;

  /// how many requests run at once, at least 1. The others wait their turn
  final int maxConcurrentRequests;

  /// the client this instance made, which [close] closes
  final http.Client? _ownedClient;

  // Keep request deduplication local to this instance. Different instances
  // may use different repositories and caches for the same NIP-05.
  final Map<String, _Flight> _flights = {};

  /// keyed by domain
  final _RecentErrors<Nip05ResolveNetworkError> _failedDomains;

  /// keyed by identifier
  final _RecentErrors<Nip05ResolveInvalidResponse> _invalidResponses;

  final _Slots _requests;

  /// how many times [abortPending] ran
  int _aborts = 0;

  bool _closed = false;

  /// [cache] keeps the resolved identifiers, in memory when null, until they
  /// are older than both [validDuration] and [notFoundDuration].
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
    Duration invalidResponseDuration = nip05InvalidResponseDuration,
    int maxConcurrentRequests = nip05MaxConcurrentRequests,
  }) {
    if (httpClient != null && nip05Repository != null) {
      throw ArgumentError(
        'Nip05Resolver takes an httpClient or a nip05Repository, not both',
      );
    }
    if (maxConcurrentRequests < 1) {
      throw ArgumentError.value(
        maxConcurrentRequests,
        'maxConcurrentRequests',
        'must be at least 1',
      );
    }
    final ownedClient = httpClient == null && nip05Repository == null
        ? http.Client()
        : null;
    return Nip05Resolver._(
      cache ??
          MemoryNip05Cache(
            maxAge: validDuration > notFoundDuration
                ? validDuration
                : notFoundDuration,
          ),
      nip05Repository ??
          HttpNip05Repository(client: httpClient ?? ownedClient!),
      ownedClient,
      validDuration: validDuration,
      notFoundDuration: notFoundDuration,
      networkErrorDuration: networkErrorDuration,
      invalidResponseDuration: invalidResponseDuration,
      maxConcurrentRequests: maxConcurrentRequests,
    );
  }

  Nip05Resolver._(
    this._cache,
    this._nip05Repository,
    this._ownedClient, {
    required this.validDuration,
    required this.notFoundDuration,
    required this.networkErrorDuration,
    required this.invalidResponseDuration,
    required this.maxConcurrentRequests,
  }) : _failedDomains = _RecentErrors(networkErrorDuration),
       _invalidResponses = _RecentErrors(invalidResponseDuration),
       _requests = _Slots(maxConcurrentRequests);

  /// Ends the calls in flight with a `RequestAbortedException` (from
  /// `package:http`), including those still reading the cache or waiting
  /// their turn: none sends a request afterwards. This instance stays usable.
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
  /// and a [Nip05ResolveInvalidResponse] for [invalidResponseDuration] to its
  /// identifier. [refresh] asks the domain whatever was remembered, such as
  /// when the user fixed their nostr.json.
  ///
  /// Concurrent calls for one identifier share one request, and at most
  /// [maxConcurrentRequests] requests run at once while the others wait their
  /// turn. One that waits on a domain found unreachable meanwhile gives that
  /// [Nip05ResolveNetworkError] without a request. An error of the cache is
  /// ignored: the call asks the domain when the cache cannot read, and gives
  /// what the domain answered when it cannot save. Throws a [StateError] once
  /// [close] ran.
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
      if (_invalidResponses[identifier] ?? _failedDomains[domain]
          case final error?) {
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

    Nip05Record? record;
    try {
      record = await _cache.loadNip05(identifier);
    } catch (_) {
      // a cache that cannot read costs a request, not the answer
    }
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
    final knownError = _failedDomains[domain];
    await _requests.take(flight.abortTrigger);
    try {
      if (flight.isAborted) {
        throw http.RequestAbortedException();
      }
      // only an error found while it waited, so that refresh still asks
      if (_failedDomains[domain] case final error?
          when !identical(error, knownError)) {
        return error;
      }
      return await _request(identifier, domain, flight);
    } finally {
      _requests.release();
    }
  }

  Future<Nip05ResolveResult> _request(
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
      final error = Nip05ResolveInvalidResponse(e);
      _failedDomains.forget(domain);
      _invalidResponses.remember(identifier, error);
      return error;
    } on Exception catch (e) {
      final error = Nip05ResolveNetworkError(e);
      if (!flight.isAborted) {
        _failedDomains.remember(domain, error);
        _invalidResponses.forget(identifier);
      }
      return error;
    }
    _failedDomains.forget(domain);
    _invalidResponses.forget(identifier);

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

/// Lets [max] requests run at once, and the others wait their turn in order
class _Slots {
  final int max;
  int _taken = 0;

  /// an aborted turn stays until [release] skips it
  final _turns = Queue<Completer<void>>();

  _Slots(this.max);

  /// completes once a request may run, or throws a `RequestAbortedException`
  /// when [abortTrigger] completes while it waits
  Future<void> take(Future<void> abortTrigger) {
    if (_taken < max) {
      _taken++;
      return Future.value();
    }
    final turn = Completer<void>();
    _turns.add(turn);
    unawaited(
      abortTrigger.then((_) {
        if (!turn.isCompleted) {
          turn.completeError(http.RequestAbortedException());
        }
      }),
    );
    return turn.future;
  }

  /// hands the slot to the next request waiting, if any
  void release() {
    while (_turns.isNotEmpty) {
      final turn = _turns.removeFirst();
      if (!turn.isCompleted) {
        turn.complete();
        return;
      }
    }
    _taken--;
  }
}

/// Errors given again, without a request, for [duration]
class _RecentErrors<E extends Nip05ResolveError> {
  final Duration duration;

  // in the order they were last remembered, so the expired ones come first
  final Map<String, ({E error, DateTime until})> _errors = {};

  _RecentErrors(this.duration);

  E? operator [](String key) {
    final entry = _errors[key];
    return entry != null && clock.now().isBefore(entry.until)
        ? entry.error
        : null;
  }

  void remember(String key, E error) {
    final now = clock.now();
    _errors
      ..remove(key)
      ..[key] = (error: error, until: now.add(duration));
    while (_errors.isNotEmpty && !now.isBefore(_errors.values.first.until)) {
      _errors.remove(_errors.keys.first);
    }
  }

  void forget(String key) => _errors.remove(key);
}
