# Getting started with Dostr

Dostr is a set of Dart packages, each covering one part of Nostr, so an app only depends on what it uses:

- [`dostr_core`](https://pub.dev/packages/dostr_core): relay connections, NIP-42 authentication, and REQ and EVENT on the relays you pick.
- [`dostr_bip340`](https://pub.dev/packages/dostr_bip340): a signer that holds a private key, and a signature verifier.
- [`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers): the metadata and relay lists of accounts, read where NIP-65 puts them.
- [`dostr_url_set`](https://pub.dev/packages/dostr_url_set): relay sets described rather than listed, resolved when needed.
- One package per NIP for the rest, listed in the [package overview](https://github.com/nogringo/dostr#monorepo-packages).

They are pure Dart unless their README says otherwise, so the same code runs in a Flutter app, a server or a CLI. In a Flutter app, [`dostr_flutter`](../packages/flutter/README.md) adds login, profile and account widgets on top of them.

## Install

```bash
dart pub add dostr_core dostr_bip340
```

## Query relays

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
      Filter(kinds: [Nip01Event.kTextNoteKind], authors: [pubkey], limit: 10),
    ],
  },
);

await for (final received in req.events) {
  print(received.event.content);
}
```

Keep one `RelayManager` for the whole app. [Relay REQs](../packages/core/README.md#relay-reqs) covers subscriptions and adding relays to a running request.

## Sign and publish

```dart
final signer = Bip340EventSigner(privateKey: privateKey, publicKey: publicKey);

final signed = await signer.sign(
  Nip01Event(
    pubKey: publicKey,
    kind: Nip01Event.kTextNoteKind,
    tags: [],
    content: 'hello nostr',
  ),
);

final outcomes = await RelayPublishes(relayManager: relays)
    .publish(signed, relays: ['wss://relay.example.com'])
    .done;
```

See [Relay publishes](../packages/core/README.md#relay-publishes). Other signers (NIP-46 bunkers, NIP-07 extensions, NIP-55 apps) implement the same `EventSigner`, see [Signers](../packages/signer/README.md#signers).

## Read where accounts publish

The examples above talk to relays you name. To read an account's events from the relays it writes to, and publish where its readers look, use [Fetchers](../packages/fetchers/README.md) and [Relay sets](../packages/url_set/README.md). [Outbox model](outbox-model.md) puts them together.

## Faster verification

`Bip340EventVerifier` checks signatures in pure Dart, on the calling isolate. On native platforms `RustEventVerifier` from [`dostr_rust_verifier`](https://pub.dev/packages/dostr_rust_verifier) is much faster. It needs the Rust toolchain, see its README. On the web, `WebEventVerifier` from [`dostr_web_crypto`](https://pub.dev/packages/dostr_web_crypto) is much faster.
