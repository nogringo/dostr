import 'relay_failure.dart';

/// hols information about a individual relay broadcast response \
/// e.g. \
/// ["OK", "b1a649ebe8...", true, "duplicate: already have this event"]
/// ["OK", "b1a649ebe8...", false, "pow: difficulty 26 is less than 30"]
class RelayBroadcastResponse {
  /// the relay url
  final String relayUrl;

  /// true if the relay responded with "OK"
  bool okReceived;

  /// true if publishing was successful
  bool broadcastSuccessful;

  /// the message of the relay's OK, usually an error message
  String msg;

  /// what kept the event from reaching the relay, or from being accepted once
  /// the relay asked for authentication
  final RelayFailure? failure;

  /// creates a new [RelayBroadcastResponse] instance
  RelayBroadcastResponse({
    required this.relayUrl,
    this.okReceived = false,
    this.broadcastSuccessful = false,
    this.msg = "",
    this.failure,
  });

  @override
  operator ==(other) =>
      other is RelayBroadcastResponse && relayUrl == other.relayUrl;

  @override
  int get hashCode => relayUrl.hashCode;
}
