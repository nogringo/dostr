import 'package:dostr_nip01/dostr_nip01.dart';

/// An event a `RelayReq` received, with the relay that sent it.
class RelayReqEvent {
  final Nip01Event event;

  /// clean url of the relay that sent [event]
  final String relayUrl;

  const RelayReqEvent(this.event, this.relayUrl);

  @override
  String toString() => 'RelayReqEvent(${event.id} from $relayUrl)';
}
