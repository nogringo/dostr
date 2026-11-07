/// What came of an event sent to one relay by a `DeliverySend`.
class DeliveryResponse {
  /// the relay url
  final String relayUrl;

  /// whether the relay answered with an OK that accepts the event
  final bool accepted;

  /// the message of the relay's OK, usually an error message
  final String message;

  /// what kept the event from reaching the relay, or from being accepted once
  /// the relay asked for authentication
  final String? failure;

  /// whether [failure] is the relay asking for an identity that the event may
  /// not reveal
  final bool identityNotAllowed;

  const DeliveryResponse({
    required this.relayUrl,
    this.accepted = false,
    this.message = '',
    this.failure,
    this.identityNotAllowed = false,
  });
}
