import 'package:ndk/ndk.dart';

Future<void> main() async {
  final ndk = Ndk.emptyBootstrapRelaysConfig();

  final pubkey = Nip19.decode(
    'npub1s5yq6wadwrxde4lhfs56gn64hwzuhnfa6r9mj476r5s4hkunzgzqrs6q7z',
  );

  final metrics = await ndk.ta.getUserMetrics(
    pubkey,
    metrics: {Nip85Metric.rank, Nip85Metric.followers},
  );
  print('rank=${metrics?.rank} followers=${metrics?.followers}');

  await ndk.destroy();
}
