# ndk_core

The core of [NDK](https://pub.dev/packages/ndk): relay connections, NIP-42
authentication, and REQ and EVENT on the relays you pick, with nothing on top.
NDK builds its cache, outbox routing and use cases on it.

Most apps want `ndk`. Use `ndk_core` on its own when you only talk to relays
you already know, for a bot, a relay tool or a NIP-46 client.

## Install

```yaml
dependencies:
  ndk_core: ^0.11.0-dev.2
  ndk_bip340: ^0.1.0
```

`ndk_core` has no signing or verification code of its own: it takes any
`EventSigner` and `EventVerifier`. [`ndk_bip340`](https://pub.dev/packages/ndk_bip340)
provides pure Dart ones.

## Usage

```dart
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';

final relays = RelayManager(
  globalState: GlobalState(),
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  bootstrapRelays: [],
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
await for (final event in req.events) {
  print(event.content);
}

final publishes = RelayPublishes(relayManager: relays);
await publishes
    .publish(signedEvent, relays: ['wss://relay.example.com'])
    .broadcastDoneFuture;
```

## Coming from `ndk`

These files used to live in `ndk`. A deep import keeps its path and changes
package: `package:ndk/shared/nips/nip01/helpers.dart` is now
`package:ndk_core/shared/nips/nip01/helpers.dart`. `package:ndk/ndk.dart`
still exports what it did.

`Bip340`, `Bip340EventSigner` and `Bip340EventVerifier` are in
[`ndk_bip340`](https://pub.dev/packages/ndk_bip340), and `Nip01Utils.signWithPrivateKey` is now
`Bip340.signEvent`. `Nip04` and `Nip44` are in
[`ndk_nip44`](https://pub.dev/packages/ndk_nip44).

`ndk_core` makes no HTTP calls: `RelayManager` reads NIP-11 documents from the
`RelayInfoRepo` you give it. `HttpRequestDS` and `RelayInfoHttpRepoImpl` stay in
`ndk` at their old paths, and the deprecated `RelayInfo.get` is gone.
