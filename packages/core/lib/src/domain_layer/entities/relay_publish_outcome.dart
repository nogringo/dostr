import 'relay_failure.dart';

/// What one relay did with a published event, from its NIP-01 OK message,
/// for example:
///
/// ```text
/// ["OK", "b1a649ebe8...", true, "duplicate: already have this event"]
/// ["OK", "b1a649ebe8...", false, "pow: difficulty 26 is less than 30"]
/// ```
///
/// A relay that did not answer yet has neither [okReceived] nor a [failure].
class RelayPublishOutcome {
  /// whether the relay answered with an OK, accepting the event or not
  final bool okReceived;

  /// whether the relay accepted the event
  final bool accepted;

  /// the message of the relay's OK, as it sent it
  final String message;

  /// what kept the event from reaching the relay, or from being accepted once
  /// the relay asked for authentication
  final RelayFailure? failure;

  const RelayPublishOutcome({
    this.okReceived = false,
    this.accepted = false,
    this.message = '',
    this.failure,
  });

  @override
  String toString() => [
    failure ?? (!okReceived ? 'pending' : (accepted ? 'accepted' : 'refused')),
    if (message.isNotEmpty) message,
  ].join(': ');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelayPublishOutcome &&
          okReceived == other.okReceived &&
          accepted == other.accepted &&
          message == other.message &&
          failure == other.failure;

  @override
  int get hashCode => Object.hash(okReceived, accepted, message, failure);
}
