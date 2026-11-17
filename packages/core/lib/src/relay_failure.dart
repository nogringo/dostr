/// What kept dostr_core from connecting to a relay, or from getting a REQ or
/// an EVENT to it.
///
/// A refusal from the relay itself is not a failure: it comes as the message
/// of its CLOSED or OK.
enum RelayFailureKind {
  /// the relay is one of `RelayManager.blockedRelays`
  blocked,

  /// the connection could not be opened
  unreachable,

  /// the connection went away before the message could be written
  connectionLost,

  /// the request ended while it waited for a slot on a full connection, or on
  /// one whose limit was not known yet
  connectionFull,

  /// the request was over before its connection opened
  requestEnded,

  /// the message is longer than the relay reads, either by the limit it
  /// publishes or by one it closed a socket over with a 1009
  messageTooLong,

  /// the identity the request had to use cannot sign
  cannotSign,

  /// no connection bound to the required identity could be opened: the
  /// `AuthHandler` refused it, or it could not connect
  noBoundConnection,

  /// the relay asked for an identity that the request may not reveal
  identityNotAllowed,

  /// the relay did not accept the AUTH
  authenticationFailed,
}

/// Why dostr_core gave up on a relay, see [RelayFailureKind].
class RelayFailure {
  final RelayFailureKind kind;

  /// what more there is to say, such as the error behind
  /// [RelayFailureKind.unreachable]
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
