---
label: Trusted Assertions (NIP-85)
order: 50
icon: agent
---

# Trusted Assertions (NIP-85)

[`dostr_nip85`](https://pub.dev/packages/dostr_nip85) reads [NIP-85](https://github.com/nostr-protocol/nips/blob/master/85.md) trusted assertions: metrics that trusted providers compute and publish for users (kind `30382`), events (kind `30383`), addressable events (kind `30384`) and external identifiers (kind `30385`). Use it when a metric would cost the device too much bandwidth or compute to work out itself.

```yaml
dependencies:
  dostr_nip85: ^0.1.0
  dostr_core: ^0.11.0-dev.2
  dostr_bip340: ^0.1.0
```

## Setup

`TrustedAssertions` asks you how to query and subscribe to a relay. Here both run on [RelayReqs](/usecases/relay-reqs.md):

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
```

`query` answers the `get*` methods and `subscribe` the `stream*` ones. Both are called once per relay of the providers asked.

## Default providers

Without `providers`, calls use `defaultProviders`, which defaults to `DEFAULT_NIP85_PROVIDERS`, served by `wss://nip85.uid.ovh`:

```dart
final metrics = await ta.getUserMetrics(
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  metrics: {Nip85Metric.rank, Nip85Metric.followers},
);

print('rank=${metrics?.rank}, followers=${metrics?.followers}');
```

## Your own providers

A provider is a `Nip85TrustedProvider`: the assertion kind, the metric, the provider's pubkey and the relay it publishes on. `Nip85TrustedProvider.fromTag` reads one from a kind `10040` tag such as `["30382:rank", "<pubkey>", "<relay>"]`.

Set them for every call:

```dart
final ta = TrustedAssertions(
  query: query,
  subscribe: subscribe,
  defaultProviders: myProviders,
);
```

or per call:

```dart
final user = await ta.getUserMetrics(
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  metrics: {Nip85Metric.rank, Nip85Metric.postCount, Nip85Metric.replyCount},
  providers: myProviders,
);

print('user rank=${user?.rank} postCount=${user?.postCount}');
```

## Streaming updates

Providers like [Cipolin](https://github.com/nogringo/cipolin/) emit progressive updates while syncing, so the `stream*` methods fit them best:

```dart
final sub = ta
    .streamUserMetrics(
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      metrics: {Nip85Metric.rank, Nip85Metric.followers, Nip85Metric.reactionsCount},
      providers: myProviders,
    )
    .listen((m) {
      print('update createdAt=${m.createdAt} rank=${m.rank} followers=${m.followers}');
    });

// closes the relay subscriptions
await sub.cancel();
```

## Event and addressable lookups

Event metrics (kind `30383`):

```dart
final eventMetrics = await ta.getEventMetrics(
  '<eventId>',
  metrics: {Nip85Metric.rank, Nip85Metric.commentCount, Nip85Metric.zapAmount},
  providers: myProviders,
);

print('event rank=${eventMetrics?.rank} comments=${eventMetrics?.commentCount}');
```

Addressable metrics (kind `30384`):

```dart
final addressMetrics = await ta.getAddressableMetrics(
  '30023:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:my-article-slug',
  metrics: {Nip85Metric.rank, Nip85Metric.reactionCount, Nip85Metric.zapCount},
  providers: myProviders,
);

print('address rank=${addressMetrics?.rank} zaps=${addressMetrics?.zapCount}');
```

`getExternalIdMetrics` and `streamExternalIdMetrics` do the same for external identifiers (kind `30385`).
