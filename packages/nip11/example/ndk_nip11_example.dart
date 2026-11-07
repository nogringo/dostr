import 'package:http/http.dart' as http;
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_nip11/ndk_nip11.dart';

/// `dart run example/ndk_nip11_example.dart wss://relay.example.com`
Future<void> main(List<String> args) async {
  final client = http.Client();
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final connectivity = Connectivy(
    relayManager,
    RelayInfoHttpRepoImpl(httpDS: NdkHttp(client)),
  );

  final info = await connectivity.getRelayInfo(args.first);
  if (info == null) {
    print('${args.first} serves no NIP-11 document');
  } else {
    print('${info.name} runs ${info.software} ${info.version}');
    print('NIP-50 search: ${info.supportsNip('50')}');
    print('max subscriptions: ${info.limitation?.maxSubscriptions}');
  }

  client.close();
  await relayManager.closeAllTransports();
}
