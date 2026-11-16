import 'package:dostr_relay_url/dostr_relay_url.dart';

void main() {
  print(cleanRelayUrl('WSS://Relay.Primal.NET:443/')); // wss://relay.primal.net
  print(cleanRelayUrl('https://relay.primal.net')); // null
  print(cleanRelayUrls(['wss://relay.ditto.pub/', 'not a url']));
  print(RelayUrl.fromUserInput('relay.primal.net')); // wss://relay.primal.net
}
