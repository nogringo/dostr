/// What kept ndk_core from opening a connection to a relay, or from getting a
/// REQ or an EVENT to it. A refusal of the relay itself is not one: it comes as
/// the message of its CLOSED or OK.
enum RelayFailureKind {
  /// the url is not a relay url
  invalidUrl,

  /// the relay is one of `RelayManager.blockedRelays`
  blocked,

  /// another attempt at opening the connection was still under way
  stillConnecting,

  /// the connection could not be opened
  unreachable,

  /// the connection went away before the message could be written
  connectionLost,

  /// the request ended while it waited for a slot on its connection, which
  /// held as many REQs as its relay accepts or had yet to learn how many
  connectionFull,

  /// the request was over before its connection opened
  requestEnded,

  /// the message is longer than the relay reads: than the limit it publishes,
  /// or than one it closed a socket over with a 1009
  messageTooLong,

  /// the identity it had to go out as cannot sign
  cannotSign,

  /// no connection bound to the identity it had to go out as could be opened:
  /// the `AuthHandler` refused it, or it could not connect
  noBoundConnection,

  /// the relay asked for an identity that this may not reveal
  identityNotAllowed,

  /// the relay did not accept the AUTH
  authenticationFailed,

  /// the veto of the caller called it off, or failed
  vetoed,
}

/// Why ndk_core gave up on a relay, see [RelayFailureKind].
class RelayFailure {
  final RelayFailureKind kind;

  /// what more there is to say, such as the error behind
  /// [RelayFailureKind.unreachable] or the reason a veto gave
  final String? detail;

  const RelayFailure(this.kind, [this.detail]);

  @override
  String toString() => detail == null ? kind.name : '${kind.name}: $detail';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelayFailure && kind == other.kind && detail == other.detail;

  @override
  int get hashCode => Object.hash(kind, detail);
}
