import 'package:ndk/ndk.dart';
import 'package:ndk_nip85/ndk_nip85.dart';

Future<void> main() async {
  final ndk = Ndk.emptyBootstrapRelaysConfig();

  final ta = TrustedAssertions(
    query: (filter, {required relay}) =>
        ndk.requests.query(filter: filter, explicitRelays: [relay]).future,
    subscribe: (filter, {required relay}) {
      final response = ndk.requests.subscription(
        filter: filter,
        explicitRelays: [relay],
      );
      return (
        events: response.stream,
        close: () => ndk.requests.closeSubscription(response.requestId),
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

  await ndk.destroy();
}
