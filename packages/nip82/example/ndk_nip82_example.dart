import 'package:ndk/ndk.dart';

Future<void> main() async {
  final ndk = Ndk.emptyBootstrapRelaysConfig();

  const app = SoftwareAppRef(
    publisher:
        '30782a8323b7c98b172c5a2af7206bb8283c655be6ddce11133611a03d5f1177',
    identifier: 'relaystr.ndk.sample',
  );
  const relays = ['wss://relay.zapstore.dev'];

  final metadata = await ndk.software.getApp(app: app, relays: relays);
  final releases = await ndk.software.getReleases(app: app, relays: relays);
  print('${metadata?.name}: ${releases.map((r) => r.version).join(', ')}');

  if (releases.isNotEmpty) {
    final assets = await ndk.software.resolveAssets(
      releases.first,
      relays: relays,
    );
    for (final asset in assets) {
      print('${asset.platforms.join(' ')} ${asset.url}');
    }
  }

  await ndk.destroy();
}
