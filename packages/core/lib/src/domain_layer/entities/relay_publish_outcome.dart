import 'relay_failure.dart';

/// What a relay did with a published event.
enum RelayPublishStatus {
  /// the relay has not answered yet
  pending,

  /// the relay answered with an OK true
  accepted,

  /// the relay answered with an OK false
  refused,

  /// the event did not reach the relay, or the relay asked for an
  /// authentication that did not land, see [RelayPublishOutcome.failure]
  failed,

  /// the publish ran into its timeout before the relay answered
  timedOut,
}

/// Where a publish stands on a single relay, from its NIP-01 OK message, for
/// example:
///
/// ```text
/// ["OK", "b1a649ebe8...", true, "duplicate: already have this event"]
/// ["OK", "b1a649ebe8...", false, "pow: difficulty 26 is less than 30"]
/// ```
class RelayPublishOutcome {
  /// what the relay did with the event
  final RelayPublishStatus status;

  /// the message of the relay's OK, as it sent it, for
  /// [RelayPublishStatus.accepted] and [RelayPublishStatus.refused]
  final String message;

  /// what kept the event from the relay, for [RelayPublishStatus.failed]
  final RelayFailure? failure;

  const RelayPublishOutcome._(this.status, {this.message = '', this.failure});

  const RelayPublishOutcome.pending() : this._(RelayPublishStatus.pending);

  const RelayPublishOutcome.accepted([String message = ''])
    : this._(RelayPublishStatus.accepted, message: message);

  const RelayPublishOutcome.refused([String message = ''])
    : this._(RelayPublishStatus.refused, message: message);

  const RelayPublishOutcome.failed(RelayFailure failure)
    : this._(RelayPublishStatus.failed, failure: failure);

  const RelayPublishOutcome.timedOut() : this._(RelayPublishStatus.timedOut);

  /// whether the relay accepted the event
  bool get accepted => status == RelayPublishStatus.accepted;

  /// whether the relay has yet to answer, while the publish goes on
  bool get isPending => status == RelayPublishStatus.pending;

  @override
  String toString() =>
      [status.name, ?failure, if (message.isNotEmpty) message].join(': ');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelayPublishOutcome &&
          status == other.status &&
          message == other.message &&
          failure == other.failure;

  @override
  int get hashCode => Object.hash(status, message, failure);
}
