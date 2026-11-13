# dostr_nip85

[NIP-85](https://github.com/nostr-protocol/nips/blob/master/85.md) trusted assertions for Nostr: metrics that trusted providers compute and publish for users (kind `30382`), events (kind `30383`), addressable events (kind `30384`) and external identifiers (kind `30385`), so the device does not have to.

It asks you how to query and subscribe to a relay.

## Install

```yaml
dependencies:
  dostr_nip85: ^0.1.0
  dostr_core: ^0.11.0-dev.2
  dostr_bip340: ^0.1.0
```

## Usage

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip85/dostr_nip85.dart';

final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relayManager,
  eventVerifier: Bip340EventVerifier(),
);

final ta = TrustedAssertions(
  query: (filter, {required relay}) => reqs
      .req(relays: {relay: [filter]})
      .events
      .map((received) => received.event)
      .toList(),
  subscribe: (filter, {required relay}) {
    final req = reqs.req(relays: {relay: [filter]}, closeOnEose: false);
    return (
      events: req.events.map((received) => received.event),
      close: req.close,
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

More in [example/](example/) and the [trusted assertions docs](https://nogringo.github.io/dostr/usecases/trusted-assertions/).
