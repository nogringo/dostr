import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_dart_package_1/ndk_dart_package_1.dart';

Future<void> main() async {
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final fetcher = Nip65Fetcher(
    reqs: RelayReqs(
      relayManager: relayManager,
      eventVerifier: Bip340EventVerifier(useIsolate: false),
    ),
  );

  const fiatjaf =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
  final event = await fetcher.fetch(fiatjaf);
  await relayManager.closeAllTransports();

  if (event == null) {
    print('no NIP-65 list found');
    return;
  }
  print('event: ${event.id}');
  print('tags:  ${event.tags}');
}
