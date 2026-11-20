part of 'nip77.dart';

/// Internal implementation of NIP-77 Negentropy sync.
///
/// **Not part of the public API.** Use [Nip77] instead.
class _Nip77Internal extends RelayProtocolHandler {
  final RelayManager _relayManager;
  final Nip77LoadEventIds _loadEventIds;

  /// in-flight reconciliations, by subscription id
  final Map<String, Nip77State> _sessions = {};

  static final Random _random = Random.secure();

  _Nip77Internal({
    required RelayManager relayManager,
    required Nip77LoadEventIds loadEventIds,
  }) : _relayManager = relayManager,
       _loadEventIds = loadEventIds;

  @override
  bool onMessage(RelayConnectionKey key, List<dynamic> message) {
    switch (message) {
      case ['NEG-MSG', final String subscriptionId, final String payload, ...]:
        _processNegMsg(subscriptionId, key, payload);
        return true;
      case ['NEG-ERR', final String subscriptionId, final String error, ...]:
        final maxRecords = message.length > 3 ? message[3] : null;
        _processNegErr(
          subscriptionId,
          key,
          error,
          maxRecords: maxRecords is num ? maxRecords.toInt() : null,
        );
        return true;
    }
    return false;
  }

  @override
  bool onClosed(
    RelayConnectionKey key,
    String subscriptionId,
    String? message,
  ) {
    if (!_sessions.containsKey(subscriptionId)) return false;
    _processNegClosed(subscriptionId, key, message);
    return true;
  }

  /// Some relays answer a NEG-OPEN they do not understand with a NOTICE, so
  /// one that looks like a refusal fails the negotiations of that connection
  /// still waiting for their first answer.
  @override
  void onNotice(RelayConnectionKey key, String message) {
    final lower = message.toLowerCase();
    final refusesNegentropy =
        lower.contains('negentropy') ||
        lower.contains('neg-') ||
        lower.contains('unsupported') ||
        lower.contains('unknown command') ||
        lower.contains('not implemented') ||
        lower.contains('nip-77');
    if (!refusesNegentropy) return;

    for (final state in _sessions.values.toList()) {
      if (state.connectionKey != key || !state.negOpenSent || state.answered) {
        continue;
      }
      _fail(state, Nip77NotSupportedException(key.url, message));
    }
  }

  @override
  bool hasWorkOn(RelayConnectionKey key) => _sessions.values.any(
    (state) => !state.isCompleted && state.connectionKey == key,
  );

  Nip77Response reconcile({
    required RelayUrl relayUrl,
    required Filter filter,
    required Duration openTimeout,
    required Duration idleTimeout,
    required int frameSizeLimit,
    List<({String id, int createdAt})>? localIds,
    AuthPolicy? auth,
  }) {
    neg.checkFrameSizeLimit(frameSizeLimit);
    // nothing can carry this reconciliation, and nothing is sent. Raised from
    // the call rather than through a future the caller has had no chance to
    // listen to yet
    final connectionKey = RelayConnectionKey.forAuth(relayUrl, auth);
    if (connectionKey == null) {
      throw Nip77AuthUnavailableException(relayUrl, auth!.signer!.publicKey);
    }

    final state = Nip77State(
      subscriptionId: _newSubscriptionId(),
      connectionKey: connectionKey,
      filter: filter,
      openTimeout: openTimeout,
      idleTimeout: idleTimeout,
      frameSizeLimit: frameSizeLimit,
      auth: auth,
    );
    _sessions[state.subscriptionId] = state;

    _startReconciliation(state, localIds: localIds);

    return Nip77Response(state);
  }

  /// Random, so reconciliations started in the same instant do not share one.
  /// A clock reading does: on the web it only changes every millisecond.
  String _newSubscriptionId() {
    final bytes = List.generate(16, (_) => _random.nextInt(256));
    return 'neg-${neg.NegentropyEncoder.bytesToHex(bytes)}';
  }

  Future<void> _startReconciliation(
    Nip77State state, {
    List<({String id, int createdAt})>? localIds,
  }) async {
    try {
      final connectivity = await _openConnection(state);
      if (state.isCompleted) {
        return; // Guard: the session may have been closed during await
      }
      if (connectivity == null) {
        _fail(state, Nip77ConnectionException(state.relayUrl));
        return;
      }

      final local = localIds ?? await _loadEventIds(state.filter);
      if (state.isCompleted) {
        return; // Guard: the session may have been closed during await
      }
      state.localItems = neg.prepareNegentropyItems([
        for (final e in local)
          neg.NegentropyItem.fromHex(timestamp: e.createdAt, idHex: e.id),
      ]);

      _sendNegOpen(state);
    } catch (e) {
      _fail(state, e);
    }
  }

  /// Opens the connection the session is bound to, handing over the account so
  /// a bound connection works for an identity that was never registered.
  Future<RelayConnectivity?> _openConnection(Nip77State state) async {
    final key = state.connectionKey;
    if (!key.isAnonymous) {
      final account = state.auth?.signer;
      if (account == null) return null;
      return _relayManager.openConnectionAs(key.url, account, pausing: state);
    }
    final opened = await _relayManager.connectRelay(key.url);
    return opened.connected ? _relayManager.connectivities[key] : null;
  }

  /// Sends NEG-OPEN on the connection the session currently holds. The initial
  /// message is rebuilt from [Nip77State.localItems], so a refused negotiation
  /// can be reopened on another connection by calling this again.
  void _sendNegOpen(Nip77State state) {
    if (state.isCompleted) return;

    final initialMessage = neg.NegentropyEncoder.createInitialMessage(
      state.localItems,
    );
    final negOpen = [
      'NEG-OPEN',
      state.subscriptionId,
      state.filter.toJson(),
      neg.NegentropyEncoder.bytesToHex(initialMessage),
    ];
    _relayManager.send(state.connectionKey, negOpen);
    state.negOpenSent = true;
    _awaitAnswer(state, state.openTimeout, openUnanswered: true);

    logger.fine(
      () => 'NEG-OPEN sent to ${state.connectionKey}: ${state.subscriptionId}',
    );
  }

  /// Gives the relay [timeout] to answer what was just sent, and ends the
  /// session if it stays silent.
  void _awaitAnswer(
    Nip77State state,
    Duration timeout, {
    required bool openUnanswered,
  }) {
    state.startTimeout(timeout, () {
      if (state.isCompleted) return;
      _sendNegClose(state.connectionKey, state.subscriptionId);
      _fail(
        state,
        Nip77TimeoutException(
          state.relayUrl,
          timeout,
          openUnanswered: openUnanswered,
        ),
      );
    });
  }

  /// The session [subscriptionId] belongs to, when the message really came
  /// from the connection it runs on. Matching the whole key, not just the url,
  /// keeps a message seen on the anonymous socket from feeding a session that
  /// moved to a bound one.
  Nip77State? _sessionFor(
    String subscriptionId,
    RelayConnectionKey key,
    String messageType,
  ) {
    final state = _sessions[subscriptionId];
    if (state == null) {
      logger.warning(
        () => 'Received $messageType for unknown session: $subscriptionId',
      );
      return null;
    }
    if (state.connectionKey != key) {
      logger.warning(
        () =>
            'Received $messageType from mismatched connection: expected '
            '${state.connectionKey}, got $key',
      );
      return null;
    }
    return state;
  }

  /// Process incoming NEG-MSG from a relay
  void _processNegMsg(
    String subscriptionId,
    RelayConnectionKey key,
    String payload,
  ) {
    final state = _sessionFor(subscriptionId, key, 'NEG-MSG');
    if (state == null) return;
    state.answered = true;

    final Uint8List? response;
    try {
      response = state.processMessage(
        neg.NegentropyEncoder.hexToBytes(payload),
      );
    } catch (e) {
      logger.severe(() => 'Error processing NEG-MSG: $e');
      _sendNegClose(key, subscriptionId);
      _fail(state, Nip77MalformedMessageException(key.url, e));
      return;
    }

    if (response == null) {
      _sendNegClose(key, subscriptionId);
      state.complete();
      _sessions.remove(subscriptionId);
      logger.fine(
        () =>
            'NEG reconciliation complete: need=${state.needIds.length}, have=${state.haveIds.length}',
      );
      return;
    }

    final responsePayload = neg.NegentropyEncoder.bytesToHex(response);
    _relayManager.send(key, ['NEG-MSG', subscriptionId, responsePayload]);
    _awaitAnswer(state, state.idleTimeout, openUnanswered: false);
    logger.fine(() => 'NEG-MSG sent to $key');
  }

  /// Process incoming NEG-ERR from a relay
  void _processNegErr(
    String subscriptionId,
    RelayConnectionKey key,
    String errorMsg, {
    int? maxRecords,
  }) {
    final state = _sessionFor(subscriptionId, key, 'NEG-ERR');
    if (state == null) return;
    state.answered = true;

    logger.severe(() => 'NEG-ERR from $key: $errorMsg');

    if (_isAuthRefusal(errorMsg)) {
      _handleNegAuthRequired(state, errorMsg);
      return;
    }

    _fail(
      state,
      Nip77RefusedException(key.url, errorMsg, maxRecords: maxRecords),
    );
  }

  /// Process a CLOSED that ends a negotiation. NIP-77 only names NEG-ERR, but
  /// relays that gate NEG-OPEN behind NIP-42 commonly refuse it the way they
  /// refuse a REQ.
  void _processNegClosed(
    String subscriptionId,
    RelayConnectionKey key,
    String? message,
  ) {
    final state = _sessionFor(subscriptionId, key, 'CLOSED');
    if (state == null) return;
    state.answered = true;

    final reason = message ?? '';
    logger.fine(
      () => 'CLOSED for negotiation $subscriptionId on $key: $reason',
    );

    if (_isAuthRefusal(reason)) {
      _handleNegAuthRequired(state, reason);
      return;
    }

    _fail(state, Nip77RefusedException(key.url, reason));
  }

  /// NIP-77 only suggests `blocked` and `closed`, so a relay that gates the
  /// negotiation behind an identity says so in the machine-readable prefixes
  /// NIP-01 defines for CLOSED.
  bool _isAuthRefusal(String message) {
    final lower = message.toLowerCase();
    return lower.contains('auth-required') || lower.contains('restricted');
  }

  void _fail(Nip77State state, Object error) {
    state.completeWithError(error);
    _sessions.remove(state.subscriptionId);
  }

  /// Reopens a refused negotiation on a connection bound to an identity, the
  /// way a refused REQ is retried.
  void _handleNegAuthRequired(Nip77State state, String message) {
    final url = state.connectionKey.url;

    // a refusal that lands mid-session cannot be replayed: the streams already
    // emitted, and a fresh NEG-OPEN would report those ids twice
    if (state.needIds.isNotEmpty || state.haveIds.isNotEmpty) {
      _fail(state, Nip77AuthRequiredException(url, message));
      return;
    }

    final account = _relayManager.accountForAuth(state.auth);
    if (account == null) {
      _fail(state, Nip77AuthRequiredException(url, message));
      return;
    }

    // the connection is already bound, so the relay wants the AUTH it has not
    // been given yet rather than another identity
    if (!state.connectionKey.isAnonymous) {
      if (state.authenticatedAfterRefusal) {
        _fail(state, Nip77AuthRequiredException(url, message));
        return;
      }
      unawaited(_authenticateAndReopen(state, message));
      return;
    }

    if (state.movedToBoundConnection) {
      _fail(state, Nip77AuthRequiredException(url, message));
      return;
    }
    unawaited(_moveToBoundConnection(state, account, message));
  }

  /// Answers the challenge on the bound connection, then reopens.
  ///
  /// No timeout runs until the NEG-OPEN is sent again: signing may sit on a
  /// remote signer waiting for a human, which is not the relay being silent.
  Future<void> _authenticateAndReopen(Nip77State state, String message) async {
    final url = state.connectionKey.url;
    state.authenticatedAfterRefusal = true;

    state.cancelTimeout();
    final bool authenticated;
    try {
      authenticated = await _relayManager.authenticateConnection(
        state.connectionKey,
      );
    } catch (e) {
      // no timeout runs while authenticating, so a session that cannot
      // authenticate has to end here rather than wait forever
      if (!state.isCompleted) {
        _fail(state, Nip77AuthRequiredException(url, '$message ($e)'));
      }
      return;
    }

    if (state.isCompleted) return;

    if (!authenticated) {
      _fail(state, Nip77AuthRequiredException(url, message));
      return;
    }
    _sendNegOpen(state);
  }

  /// Moves a refused anonymous negotiation onto a connection bound to
  /// [account]. No timeout runs for the same reason as above: opening that
  /// connection is not the relay being silent.
  Future<void> _moveToBoundConnection(
    Nip77State state,
    NostrSigner account,
    String message,
  ) async {
    final url = state.connectionKey.url;
    state.movedToBoundConnection = true;

    logger.fine(
      () =>
          'AUTH required for negotiation ${state.subscriptionId} on $url, '
          'retrying as ${account.publicKey}',
    );

    state.cancelTimeout();
    final RelayConnectivity? bound;
    try {
      bound = await _relayManager.openConnectionAs(url, account);
    } catch (e) {
      if (!state.isCompleted) {
        _fail(state, Nip77AuthRequiredException(url, '$message ($e)'));
      }
      return;
    }

    if (state.isCompleted) return;

    if (bound == null) {
      _fail(state, Nip77AuthRequiredException(url, message));
      return;
    }
    state.connectionKey = bound.key;
    // sent without waiting for the AUTH: a relay that only challenges on
    // demand needs this NEG-OPEN as the trigger, and the challenge it then
    // sends authenticates the bound connection on its own
    _sendNegOpen(state);
  }

  void _sendNegClose(RelayConnectionKey key, String subscriptionId) {
    _relayManager.send(key, ['NEG-CLOSE', subscriptionId]);
    logger.fine(() => 'NEG-CLOSE sent to $key: $subscriptionId');
  }

  void close(String subscriptionId) {
    final state = _sessions[subscriptionId];
    if (state != null) {
      _sendNegClose(state.connectionKey, subscriptionId);
      state.close();
      _sessions.remove(subscriptionId);
    }
  }

  void closeAll() {
    for (final entry in _sessions.entries.toList()) {
      _sendNegClose(entry.value.connectionKey, entry.key);
      entry.value.close();
    }
    _sessions.clear();
  }
}
