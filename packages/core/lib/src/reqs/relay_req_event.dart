import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';

/// An event a `RelayReq` received, with the relay that sent it.
class RelayReqEvent {
  final Nip01Event event;

  /// the relay that sent [event]
  final RelayUrl relayUrl;

  const RelayReqEvent(this.event, this.relayUrl);

  @override
  String toString() => 'RelayReqEvent(${event.id} from $relayUrl)';
}
