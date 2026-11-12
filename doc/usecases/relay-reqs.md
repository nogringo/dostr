---
icon: plug
label: Relay REQs
---

# Relay REQs

A NIP-01 REQ on relays you pick, from [`ndk_core`](https://pub.dev/packages/ndk_core): no cache, no outbox routing, no merging of identical requests, no pagination. To ask the relays where an account publishes, see [Fetchers](fetchers.md).

## Setup

```yaml
dependencies:
  ndk_core: ^0.11.0-dev.2
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';

final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relays,
  eventVerifier: Bip340EventVerifier(),
);
```

Keep one `RelayManager` for the whole app: it holds the connections, which every `RelayReqs` and `RelayPublishes` built on it shares.

## Query

```dart
final req = reqs.req(
  relays: {
    'wss://relay.example.com': [
      Filter(kinds: [1], authors: [pubkey], limit: 20),
    ],
  },
  timeout: Duration(seconds: 10),
);

final events = await req.events.toList();
// per relay: eose, closed, notSent, disconnected or timedOut
final outcomes = await req.done;
```

## Subscription

```dart
final sub = reqs.req(
  relays: {for (final url in relayUrls) url: [filter]},
  closeOnEose: false,
);

final listener = sub.events.listen(onEvent);

// sends the CLOSE, as sub.close() does
await listener.cancel();
```

## Adding relays as you find them

Without `relays`, the request stays open until you `seal()` it, so a relay that answers fast does not end it while you are still picking the others:

```dart
final req = reqs.req();
req.send('wss://a.example.com', [filterA]);
req.send('wss://b.example.com', [filterB]);
req.seal();
```

Each relay takes one `send`. Its filters travel in a single REQ, since a second REQ with the same id replaces the first on the relay.

A relay can still be added after `seal()` while the request runs: it then has to answer too before the request ends. `send` returns `false` and sends nothing once the request is over, for a url that is not a relay's, and for a relay the request was already sent to.

## What you get

- Events are signature-checked, and invalid ones are dropped.
- Each event comes as a `RelayReqEvent`: the `event`, and the `relayUrl` that sent it.
- Events are not deduplicated: an event two relays hold arrives twice, once from each. `events.map((e) => e.event).distinctUnique()` from rxdart keeps each one once.
- `events` is a single-subscription stream.
- `auth` takes an `AuthPolicy`, see [NIP-42 authentication](/concepts/nip42-auth.md).

[Relay publishes](relay-publishes.md) is the writing counterpart.
