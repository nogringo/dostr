---
label: Trusted Assertions (NIP-85)
order: 50
icon: agent
---

[!badge variant="primary" text="low level"]

## When to use

Trusted assertions are data events computed by a provider. It's useful when certain operations might be too expensive (bandwidth, compute) on the edge device.

## Setup

Trusted assertions live in the `ndk_nip85` package.

```yaml
dependencies:
  ndk_nip85: ^0.1.0
```

```dart
import 'package:ndk_nip85/ndk_nip85.dart';

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
```

`ndk_nip85` does not depend on `ndk`, so `TrustedAssertions` takes how to reach a relay: `query` answers the `get*` methods and `subscribe` the `stream*` ones.

## 1) Option A: Use the default trusted providers

`TrustedAssertions` uses `DEFAULT_NIP85_PROVIDERS` unless told otherwise.

```dart
final metrics = await ta.getUserMetrics(
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  metrics: {Nip85Metric.rank, Nip85Metric.followers},
);

print('rank=${metrics?.rank}, followers=${metrics?.followers}');
```

## 2) Option B: Override providers with your Cipolin instance

For every call:

```dart
final ta = TrustedAssertions(
  query: query,
  subscribe: subscribe,
  defaultProviders: APP_DEFAULT_NIP85_PROVIDERS,
);
```

or per request:

```dart
final user = await ta.getUserMetrics(
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  metrics: {Nip85Metric.rank, Nip85Metric.postCount, Nip85Metric.replyCount},
  providers: providers,
);

print('user rank=${user?.rank} postCount=${user?.postCount}');
```

## 3) Streaming updates (recommended for trust providers that stream their values like cipolin)

Providers like [Cipolin](https://github.com/nogringo/cipolin/) emit progressive updates while syncing, so streaming APIs are the best fit.

```dart
final sub = ta
    .streamUserMetrics(
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      metrics: {Nip85Metric.rank, Nip85Metric.followers, Nip85Metric.reactionsCount},
      providers: providers,
    )
    .listen((m) {
      print('update createdAt=${m.createdAt} rank=${m.rank} followers=${m.followers}');
    });

// Later: closes the relay subscriptions
await sub.cancel();
```

## 4) Event and addressable lookups

Event metrics (kind 30383):

```dart
final eventMetrics = await ta.getEventMetrics(
  '<eventId>',
  metrics: {Nip85Metric.rank, Nip85Metric.commentCount, Nip85Metric.zapAmount},
  providers: providers,
);

print('event rank=${eventMetrics?.rank} comments=${eventMetrics?.commentCount}');
```

Addressable metrics (kind 30384):

```dart
final addressMetrics = await ta.getAddressableMetrics(
  '30023:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:my-article-slug',
  metrics: {Nip85Metric.rank, Nip85Metric.reactionCount, Nip85Metric.zapCount},
  providers: providers,
);

print('address rank=${addressMetrics?.rank} zaps=${addressMetrics?.zapCount}');
```
