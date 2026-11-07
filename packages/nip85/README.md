# ndk_nip85

[NIP-85](https://github.com/nostr-protocol/nips/blob/master/85.md) trusted assertions for [NDK](https://pub.dev/packages/ndk): metrics that trusted providers compute and publish for users (kind `30382`), events (kind `30383`), addressable events (kind `30384`) and external identifiers (kind `30385`), so the device does not have to.

It does not depend on `ndk`. It asks you how to query and subscribe to a relay. NDK exposes it, wired to its requests and `NdkConfig.defaultTrustedProviders`, as `ndk.ta`: build it yourself, as below, only to wire it differently.

## Install

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_nip85: ^0.1.0
```

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_nip85/ndk_nip85.dart';

final ndk = Ndk.defaultConfig();
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

final user = await ta.getUserMetrics(
  pubkey,
  metrics: {Nip85Metric.rank, Nip85Metric.followers},
);
print('rank=${user?.rank} followers=${user?.followers}');

final sub = ta.streamUserMetrics(pubkey).listen((m) => print(m.rank));
await sub.cancel();
```

`query` answers the `get*` methods and `subscribe` the `stream*` ones. Both are called once per relay of the providers asked. `defaultProviders` defaults to `DEFAULT_NIP85_PROVIDERS`, served by `wss://nip85.uid.ovh`, and each call can pass its own `providers` instead.

More in [example/](example/) and the [trusted assertions docs](https://dart-nostr.com/usecases/trusted-assertions/).
