import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip19/ndk_nip19.dart';
import 'package:ndk_nip85/ndk_nip85.dart';

Future<void> main() async {
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final reqs = RelayReqs(
    relayManager: relayManager,
    eventVerifier: Bip340EventVerifier(),
  );
  final ta = TrustedAssertions(
    query: (filter, {required relay}) => reqs
        .req(
          relays: {
            relay: [filter],
          },
          timeout: const Duration(seconds: 10),
        )
        .events
        .map((received) => received.event)
        .toList(),
    subscribe: (filter, {required relay}) {
      final req = reqs.req(
        relays: {
          relay: [filter],
        },
        closeOnEose: false,
      );
      return (
        events: req.events.map((received) => received.event),
        close: req.close,
      );
    },
  );

  final pubkey = Nip19.decode(
    'npub1s5yq6wadwrxde4lhfs56gn64hwzuhnfa6r9mj476r5s4hkunzgzqrs6q7z',
  );

  final metrics = await ta.getUserMetrics(
    pubkey,
    metrics: {Nip85Metric.rank, Nip85Metric.followers},
  );
  print('rank=${metrics?.rank} followers=${metrics?.followers}');

  await relayManager.closeAllTransports();
}
