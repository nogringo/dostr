---
icon: plug
---

[!badge variant="primary" text="low level"]

A NIP-01 REQ on relays you pick, with nothing on top: no cache, no outbox
routing, no merging of identical requests, no pagination. [Requests](requests.md)
adds all of that on the same network path.

## Query

```dart
final req = ndk.relayReqs.req(
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
final sub = ndk.relayReqs.req(
  relays: {for (final url in relays) url: [filter]},
  closeOnEose: false,
);

final listener = sub.events.listen(onEvent);

// sends the CLOSE, as sub.close() does
await listener.cancel();
```

## Adding relays as you find them

Without `relays`, the request stays open until you `seal()` it, so a relay that
answers fast does not end it while you are still picking the others:

```dart
final req = ndk.relayReqs.req();
req.send('wss://a.example.com', [filterA]);
req.send('wss://b.example.com', [filterB]);
req.seal();
```

Each relay takes one `send`. Its filters travel in a single REQ, since a second
REQ with the same id replaces the first on the relay.

## What you get

- Events are signature-checked, and invalid ones are dropped.
- Events are not deduplicated: an event two relays hold arrives twice, each
  copy with its relay in `sources`. `events.distinctUnique()` from rxdart keeps
  each one once.
- `events` is a single-subscription stream.
- `auth` takes the same `AuthPolicy` as [Requests](requests.md).
