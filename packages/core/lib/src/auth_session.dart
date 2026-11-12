import 'dart:async';

import 'package:ndk_signer/ndk_signer.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import '../domain_layer/entities/relay_connection_key.dart';
import 'logger/logger.dart';
import 'client_msg.dart';

/// NIP-42 on one socket of a connection: the challenge the relay sent on it,
/// the AUTH waiting for its OK, and whether the relay accepted it.
///
/// A session lasts as long as one socket. Once [end]ed, nothing an
/// authentication started on it can land on the socket that took its place.
class AuthSession {
  static const _kAuthKind = 22242;

  AuthSession(
    this.key, {
    required this.challengeTimeout,
    required this.okTimeout,
  });

  final RelayConnectionKey key;

  /// how long to wait for the challenge once authentication was asked for
  final Duration challengeTimeout;

  /// how long to wait for the OK of an AUTH
  final Duration okTimeout;

  String? _challenge;
  Completer<String?>? _challengeWaiter;
  Future<bool>? _authenticating;
  ({String eventId, Completer<bool> ok})? _pendingAuth;
  bool _authenticated = false;
  bool _ended = false;

  /// whether the relay accepted an AUTH on this socket
  bool get authenticated => _authenticated;

  /// whether an authentication is under way on this socket
  bool get authenticating => _authenticating != null;

  /// whether the socket is gone
  bool get ended => _ended;

  void receiveChallenge(String challenge) {
    _challenge = challenge;
    final waiter = _challengeWaiter;
    _challengeWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete(challenge);
  }

  /// Takes the OK of [eventId] when it answers the AUTH sent on this socket.
  bool receiveOk(String eventId, bool accepted) {
    final pending = _pendingAuth;
    if (pending == null || pending.eventId != eventId) return false;
    _pendingAuth = null;
    if (!pending.ok.isCompleted) pending.ok.complete(accepted);
    return true;
  }

  /// Answers the challenge as [account] with an AUTH handed to [send], and
  /// completes with whether the relay accepted it. Concurrent callers share a
  /// single AUTH.
  Future<bool> authenticate(
    Account? account,
    void Function(List<dynamic> message) send,
  ) {
    if (_authenticated) return Future.value(true);
    return _authenticating ??= _authenticate(
      account,
      send,
    ).whenComplete(() => _authenticating = null);
  }

  Future<bool> _authenticate(
    Account? account,
    void Function(List<dynamic> message) send,
  ) async {
    if (account == null) {
      Logger.log.w(() => "Cannot authenticate $key, no account for its pubkey");
      return false;
    }
    if (!account.signer.canSign()) {
      Logger.log.w(() => "Cannot authenticate $key, signer cannot sign");
      return false;
    }

    // the relay may send its challenge before or with the refusal, so waiting
    // is safe here: something already asked us to authenticate
    final challenge = await _nextChallenge();
    if (challenge == null || _ended) return false;

    // signing throws for anything from a declined request to an unreachable
    // signer, and a caller that paused its timeout to wait for it would never
    // resume that timeout if the error escaped here
    final Nip01Event signedAuth;
    try {
      signedAuth = await account.signer.sign(
        Nip01Event(
          pubKey: account.pubkey,
          kind: _kAuthKind,
          tags: [
            ["relay", key.url],
            ["challenge", challenge],
          ],
          content: '',
        ),
      );
    } catch (error, stackTrace) {
      Logger.log.w(
        () => "Could not sign AUTH for $key",
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
    if (_ended) return false;

    final ok = Completer<bool>();
    _pendingAuth = (eventId: signedAuth.id, ok: ok);
    send(ClientMsg(ClientMsgType.kAuth, event: signedAuth).toJson());
    Logger.log.d(() => "AUTH sent on $key");

    final accepted = await ok.future.timeout(
      okTimeout,
      onTimeout: () {
        Logger.log.w(
          () => "AUTH callback timeout for ${signedAuth.id} on $key",
        );
        return false;
      },
    );
    if (identical(_pendingAuth?.ok, ok)) _pendingAuth = null;
    if (!accepted || _ended) return false;
    _authenticated = true;
    return true;
  }

  /// Only call this once something has asked for authentication, otherwise a
  /// relay that only challenges on demand would never answer.
  Future<String?> _nextChallenge() async {
    final stored = _challenge;
    if (stored != null || _ended) return stored;
    final waiter = _challengeWaiter ??= Completer<String?>();
    final challenge = await waiter.future.timeout(
      challengeTimeout,
      onTimeout: () => null,
    );
    if (identical(_challengeWaiter, waiter)) _challengeWaiter = null;
    if (challenge == null) Logger.log.w(() => "No AUTH challenge from $key");
    return challenge;
  }

  /// The socket is gone: whatever is still waiting resolves to nothing.
  void end() {
    _ended = true;
    final waiter = _challengeWaiter;
    _challengeWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete(null);
    final pending = _pendingAuth;
    _pendingAuth = null;
    if (pending != null && !pending.ok.isCompleted) pending.ok.complete(false);
  }
}
