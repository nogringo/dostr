import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_dart_package_1/ndk_dart_package_1.dart';

Future<void> main() async {
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final verifier = Bip340EventVerifier(useIsolate: false);
  final reqs = RelayReqs(relayManager: relayManager, eventVerifier: verifier);
  final homeRelayList = await HomeRelayList.fetch(verifier: verifier);
  final nip65 = Nip65Fetcher(reqs: reqs, homeRelayList: homeRelayList);
  final metadata = MetadataFetcher(reqs: reqs, nip65Fetcher: nip65);
  final dmRelays = DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65);
  final blossomServers = BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65);

  const fiatjaf =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
  print('home relays: ${homeRelayList.homeRelaysOf(fiatjaf)}');
  final clock = Stopwatch()..start();
  await for (final profile in metadata.watch(fiatjaf)) {
    print('${clock.elapsedMilliseconds} ms, version of ${profile.createdAt}:');
    print('  ${profile.content}');
  }
  print('${clock.elapsedMilliseconds} ms, every relay answered');

  final dmRelayList = await dmRelays.fetch(fiatjaf);
  print(
    dmRelayList == null
        ? 'no DM relays'
        : 'DM relays: ${dmRelaysOf(dmRelayList)}',
  );

  final serverList = await blossomServers.fetch(fiatjaf);
  print(
    serverList == null
        ? 'no Blossom servers'
        : 'Blossom servers: ${blossomServersOf(serverList)}',
  );
  await relayManager.closeAllTransports();
}
