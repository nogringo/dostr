import 'package:ndk/ndk.dart';
import 'package:ndk_nip82/ndk_nip82.dart';

Future<void> main() async {
  final ndk = Ndk.emptyBootstrapRelaysConfig();

  final software = Software(
    query: (filter, {relays, timeout}) async {
      final response = ndk.requests.query(
        filter: filter,
        explicitRelays: relays,
        timeout: timeout,
      );
      final events = await response.future;
      return (
        events: events,
        anyRelayCompleted: response.relayOutcomes.values.any(
          (outcome) => outcome.status == RelayRequestStatus.eose,
        ),
      );
    },
    subscribe: (filter, {relays}) {
      final response = ndk.requests.subscription(
        filter: filter,
        explicitRelays: relays,
      );
      return (
        events: response.stream,
        close: () => ndk.requests.closeSubscription(response.requestId),
      );
    },
  );

  const app = SoftwareAppRef(
    publisher:
        '30782a8323b7c98b172c5a2af7206bb8283c655be6ddce11133611a03d5f1177',
    identifier: 'relaystr.ndk.sample',
  );
  const relays = ['wss://relay.zapstore.dev'];

  final metadata = await software.getApp(app: app, relays: relays);
  final releases = await software.getReleases(app: app, relays: relays);
  print('${metadata?.name}: ${releases.map((r) => r.version).join(', ')}');

  if (releases.isNotEmpty) {
    final assets = await software.resolveAssets(releases.first, relays: relays);
    for (final asset in assets) {
      print('${asset.platforms.join(' ')} ${asset.url}');
    }
  }

  await ndk.destroy();
}
