# dostr_core

The core of [NDK](https://pub.dev/packages/ndk): relay connections, NIP-42
authentication, and REQ and EVENT on the relays you pick, with nothing on top.
NDK builds its cache, outbox routing and use cases on it.

Most apps want `ndk`. Use `dostr_core` on its own when you only talk to relays
you already know, for a bot, a relay tool or a NIP-46 client.

## Install

```yaml
dependencies:
  dostr_core: ^0.11.0-dev.2
  dostr_bip340: ^0.1.0
```

`dostr_core` has no signing or verification code of its own: it takes any
`EventSigner` and `EventVerifier`. [`dostr_bip340`](https://pub.dev/packages/dostr_bip340)
provides pure Dart ones.

## Usage

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';

final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);

final reqs = RelayReqs(
  relayManager: relays,
  eventVerifier: Bip340EventVerifier(),
);
final req = reqs.req(
  relays: {
    'wss://relay.example.com': [
      Filter(kinds: [1], limit: 10),
    ],
  },
);
await for (final received in req.events) {
  print('${received.relayUrl}: ${received.event.content}');
}

final publishes = RelayPublishes(relayManager: relays);
final outcomes = await publishes
    .publish(signedEvent, relays: ['wss://relay.example.com'])
    .done;
```

## Coming from `ndk`

What moved and what changed is in the
[changelog](https://pub.dev/packages/dostr_core/changelog).
