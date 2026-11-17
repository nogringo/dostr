import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../connections/relay_connection.dart';
import '../connections/relay_connection_key.dart';
import '../helpers/logger.dart';
import '../helpers/timeout_pausable.dart';
import 'auth_session.dart';

/// NIP-42 for a `RelayManager`. Internal to dostr_core.
///
/// It knows which identity each connection may authenticate as, and keeps the
/// session of its current socket.
class RelayAuth {
  /// the registered accounts, which own the signers of their pubkeys
  final AuthAccounts? _accounts;

  /// asked before a connection bound to an identity is opened, see [AuthHandler]
  final AuthHandler? authHandler;

  /// how long an AUTH waits for its OK
  final Duration okTimeout;

  /// how long to wait for a NIP-42 challenge once authentication was asked for
  final Duration challengeTimeout;

  /// in flight [authHandler] questions, so concurrent openings ask once
  final Map<RelayConnectionKey, Future<bool>> _consents = {};

  RelayAuth({
    AuthAccounts? accounts,
    this.authHandler,
    required this.okTimeout,
    required this.challengeTimeout,
  }) : _accounts = accounts;

  /// The session on the current socket of [connection], opened on first use.
  AuthSession sessionOf(RelayConnection connection) =>
      connection.authSession ??= AuthSession(
        connection.key,
        challengeTimeout: challengeTimeout,
        okTimeout: okTimeout,
      );

  /// The signer that [key] authenticates with.
  ///
  /// A registered account comes first, because [AuthAccounts] owns the
  /// lifetime of its signer. Otherwise it is [openedAs], the signer the caller
  /// handed to [AuthPolicy], which does not have to be registered. Both have
  /// the pubkey of [key], so this picks a signer, never an identity.
  NostrSigner? accountFor(RelayConnectionKey key, {NostrSigner? openedAs}) {
    final pubkey = key.pubkey;
    if (pubkey == null) return null;
    return _accounts?.getAccount(pubkey) ?? openedAs;
  }

  /// Answers the challenge for [connection] with an AUTH handed to [send], and
  /// completes once the relay accepted it. Concurrent callers share a single
  /// AUTH.
  Future<bool> authenticate(
    RelayConnection connection,
    void Function(List<dynamic> message) send,
  ) => sessionOf(connection).authenticate(
    accountFor(connection.key, openedAs: connection.account),
    send,
  );

  /// Whether a new connection bound to the identity of [key] may open. The
  /// question goes to [authHandler], with [pausing] paused while it decides.
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
      logger.warning(() => "AuthHandler failed for $key", error, stackTrace);
      return false;
    }
  }

  /// Account [auth] authenticates as, null when it must stay unattributable.
  NostrSigner? accountForAuth(AuthPolicy? auth) {
    switch (auth) {
      case AuthPolicyNever():
        return null;
      case AuthPolicyAllow(:final signer):
      case AuthPolicyRequire(:final signer):
        return signer.canSign ? signer : null;
      case null:
        // a request that says nothing reveals nothing unless an AuthHandler is
        // there to agree to it
        return authHandler == null ? null : _loggedSigner();
    }
  }

  NostrSigner? _loggedSigner() {
    final logged = _accounts?.getLoggedAccount();
    return logged != null && logged.canSign ? logged : null;
  }

  /// Account a publish under [auth] authenticates as, null when it must stay
  /// unattributable.
  ///
  /// A caller that named an identity gets that one. A publish without [auth]
  /// authenticates only when an [AuthHandler] is there to agree to it. It then
  /// prefers the author of the event, and falls back to the logged-in account
  /// for gift wraps and other events whose author has no account.
  NostrSigner? accountForPublish(AuthPolicy? auth, Nip01Event event) {
    if (auth != null) {
      return accountForAuth(auth);
    }
    if (authHandler == null) {
      return null;
    }

    final author = _accounts?.getAccount(event.pubkey);
    if (author != null && author.canSign) {
      return author;
    }
    return _loggedSigner();
  }
}
