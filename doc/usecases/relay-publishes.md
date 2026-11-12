---
icon: upload
label: Relay publishes
---

# Relay publishes

Publishes a signed event to relays you pick (NIP-01 EVENT), from [`ndk_core`](https://pub.dev/packages/ndk_core): no signing, no cache, no outbox routing, no retry. To publish where the outbox model says, resolve the relays with a [UrlSet](relay-sets.md) first.

## Usage

```dart
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';

final publishes = RelayPublishes(relayManager: relays);

final signed = await signer.sign(event);

final outcomes = await publishes
    .publish(
      signed,
      relays: ['wss://relay.example.com', 'wss://other.example.com'],
      timeout: Duration(seconds: 5),
    )
    .done;

for (final response in outcomes.values) {
  print('${response.relayUrl}: ${response.broadcastSuccessful} ${response.msg}');
}
```

`relays` is the `RelayManager` of the app, see [Relay REQs](relay-reqs.md#setup).

## What you get

- Each relay gets the event once, whatever the list holds twice.
- A relay that cannot be reached is reported as failed, with the reason in `msg` and `failure`, instead of waiting for the timeout.
- `done` completes once every relay answered, once `considerDonePercent` of them accepted the event, or after `timeout`. `outcomes` and `outcomesStream` show the answers as they come, keyed by relay url like those of [Relay REQs](relay-reqs.md).
- `auth` takes an `AuthPolicy`: a relay that answers `auth-required` gets the event again on a connection bound to the account it allows, see [NIP-42 authentication](/concepts/nip42-auth.md).
- An unsigned event is refused with an `ArgumentError`.
