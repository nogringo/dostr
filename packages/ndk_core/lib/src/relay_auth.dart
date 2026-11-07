import 'dart:async';

import 'package:ndk_signer/ndk_signer.dart';
import '../domain_layer/entities/timeout_pausable.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import '../domain_layer/entities/relay_connection_key.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'auth_session.dart';

/// NIP-42 for a `RelayManager`: who each connection may authenticate as, and
/// the session on its current socket. Internal to ndk_core.
class RelayAuth {
  /// signer for nip-42 AUTH challenges from relays
  final AuthAccounts? _accounts;

  /// asked before a connection bound to an identity is opened, see [AuthHandler]
  final AuthHandler? authHandler;

  /// timeout for AUTH callbacks (how long to wait for AUTH OK)
  final Duration okTimeout;

  /// how long to wait for a NIP-42 challenge once authentication was asked for
  final Duration challengeTimeout;

  /// NIP-42 on the current socket of each connection, see [forget]
  final Map<RelayConnectionKey, AuthSession> _sessions = {};

  /// the account a connection was opened as, for identities the caller handed
  /// over instead of registering. A challenge can arrive long after whatever
  /// asked for that identity is gone, so the connection has to keep it
  final Map<RelayConnectionKey, Account> _boundAccounts = {};

  /// in flight [authHandler] questions, so concurrent openings ask once
  final Map<RelayConnectionKey, Future<bool>> _consents = {};

  RelayAuth({
    AuthAccounts? accounts,
    this.authHandler,
    required this.okTimeout,
    required this.challengeTimeout,
  }) : _accounts = accounts;

  /// The session on the current socket of [key], opened on first use.
  AuthSession sessionOf(RelayConnectionKey key) => _sessions.putIfAbsent(
    key,
    () => AuthSession(
      key,
      challengeTimeout: challengeTimeout,
      okTimeout: okTimeout,
    ),
  );

  /// The session on the current socket of [key], if anything opened one.
  AuthSession? existingSessionOf(RelayConnectionKey key) => _sessions[key];

  bool isAuthenticated(RelayConnectionKey key) =>
      _sessions[key]?.authenticated ?? false;

  bool isAuthenticating(RelayConnectionKey key) =>
      _sessions[key]?.authenticating ?? false;

  /// Ends the NIP-42 session of [key]'s socket. Call this whenever the socket
  /// dies or gets replaced: what is still in flight then resolves to false
  /// instead of landing on the socket that took its place.
  void forget(RelayConnectionKey key) => _sessions.remove(key)?.end();

  /// Keeps [account] as the identity the connection behind [key] signs as.
  void bind(RelayConnectionKey key, Account account) =>
      _boundAccounts[key] = account;

  void unbind(RelayConnectionKey key) => _boundAccounts.remove(key);

  /// The account [key] authenticates as. A registered account wins, because
  /// [AuthAccounts] owns its signer's lifetime; otherwise it is the one the
  /// caller handed to [AuthPolicy], which never had to be registered. Both
  /// carry [RelayConnectionKey.pubkey], so this only picks a signer, never an
  /// identity.
  Account? accountFor(RelayConnectionKey key) =>
      _accounts?.accounts[key.pubkey] ?? _boundAccounts[key];

  /// Answers the challenge for [key] with an AUTH handed to [send], and
  /// completes once the relay accepted it. Concurrent callers share a single
  /// AUTH.
  Future<bool> authenticate(
    RelayConnectionKey key,
    void Function(List<dynamic> message) send,
  ) => sessionOf(key).authenticate(accountFor(key), send);

  /// Whether a new connection bound to [key]'s identity may be opened, put to
  /// [authHandler] with [pausing] paused while it decides.
  Future<bool> consent(
    RelayConnectionKey key, {
    TimeoutPausable? pausing,
  }) async {
    final handler = authHandler;
    if (handler == null) {
      return true;
    }
    var asking = _consents[key];
    if (asking == null) {
      final question = _ask(handler, key);
      _consents[key] = asking = question;
      question.whenComplete(() {
        if (identical(_consents[key], question)) {
          _consents.remove(key);
        }
      });
    }
    pausing?.pauseTimeout();
    try {
      return await asking;
    } finally {
      pausing?.resumeTimeout();
    }
  }

  Future<bool> _ask(AuthHandler handler, RelayConnectionKey key) async {
    try {
      return await handler(key.url, key.pubkey!);
    } catch (error, stackTrace) {
      Logger.log.w(
        () => "AuthHandler failed for $key",
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Account [auth] authenticates as, null when it must stay unattributable.
  Account? accountForAuth(AuthPolicy? auth) {
    switch (auth) {
      case AuthPolicyNever():
        return null;
      case AuthPolicyAllow(:final account):
      case AuthPolicyRequire(:final account):
        return account.signer.canSign() ? account : null;
      case null:
        // a request that says nothing reveals nothing unless an AuthHandler is
        // there to agree to it
        return authHandler == null ? null : _loggedSigner();
    }
  }

  Account? _loggedSigner() {
    final logged = _accounts?.getLoggedAccount();
    return logged != null && logged.signer.canSign() ? logged : null;
  }

  /// Account a broadcast under [auth] authenticates as, null when it must stay
  /// unattributable.
  ///
  /// A caller that named an identity gets that one, with no heuristic. Only a
  /// broadcast that said nothing prefers the event author, because gift wraps
  /// and other ephemeral-author events have no matching account, and only once
  /// an [AuthHandler] is there to agree to it.
  Account? accountForBroadcast(AuthPolicy? auth, Nip01Event event) {
    if (auth != null) {
      return accountForAuth(auth);
    }
    if (authHandler == null) {
      return null;
    }

    final author = _accounts?.accounts[event.pubKey];
    if (author != null && author.signer.canSign()) {
      return author;
    }
    return _loggedSigner();
  }
}
