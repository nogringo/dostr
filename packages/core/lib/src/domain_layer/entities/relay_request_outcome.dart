import 'relay_failure.dart';

/// What a relay did with a request.
///
/// Declared in collapse precedence order: one request can run on several
/// connections to the same relay, an anonymous one handed over to an
/// authenticated one, and the url reports the first of these its connections
/// reached.
enum RelayRequestStatus {
  // No `queued` value: it would break the exhaustive switches of apps.
  /// the relay has not ended the request, it may still send events. A request
  /// still waiting for a slot on a full connection is pending too
  pending,

  /// the relay sent an EOSE, it has given everything it stored. A
  /// subscription stays open on it for new events
  eose,

  /// the relay ended the request itself with a CLOSED
  closed,

  /// the connection went away before the relay ended the request
  disconnected,

  /// the request ran into its timeout before the relay ended it
  timedOut,

  /// the request never reached the relay
  notSent,
}

/// Where a request stands on a single relay, and why
class RelayRequestOutcome {
  /// what the relay did with the request
  final RelayRequestStatus status;

  /// the message of the relay's CLOSED, as it sent it
  final String? message;

  /// what kept the request from being sent, for [RelayRequestStatus.notSent]
  final RelayFailure? failure;

  /// creates a new [RelayRequestOutcome]
  const RelayRequestOutcome(this.status, {this.message, this.failure});

  @override
  String toString() => [status.name, ?message, ?failure].join(': ');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelayRequestOutcome &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          message == other.message &&
          failure == other.failure;

  @override
  int get hashCode => Object.hash(status, message, failure);
}
