import 'package:dostr_relay_url/dostr_relay_url.dart';

void main() {
  print(
    RelayUrl.tryParse('WSS://Relay.Primal.NET:443/'),
  ); // wss://relay.primal.net
  print(RelayUrl.tryParse('https://relay.primal.net')); // null
  print(
    ['wss://relay.ditto.pub/', 'not a url'].map(RelayUrl.tryParse).nonNulls,
  );
  print(RelayUrl.fromUserInput('relay.primal.net')); // wss://relay.primal.net
}
