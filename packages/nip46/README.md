# ndk_nip46

[NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) remote signing for Nostr: connect to a bunker with a `bunker://` URL, or let it connect to you with a `nostrconnect://` URL, then sign events and encrypt or decrypt NIP-04 and NIP-44 messages through it.

It implements the `EventSigner` of [`ndk_signer`](https://pub.dev/packages/ndk_signer), so NDK accounts can use it. It runs on [`ndk_core`](https://pub.dev/packages/ndk_core) and does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes it as `ndk.bunkers`:

```dart
import 'package:ndk/ndk.dart';

await ndk.accounts.loginWithBunkerUrl(
  bunkerUrl: 'bunker://...',
  bunkers: ndk.bunkers,
  authCallback: (url) {},
);
```

## Standalone

```yaml
dependencies:
  ndk_nip46: ^0.1.0
  ndk_core: ^0.11.0-dev.2
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip46/ndk_nip46.dart';

final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final bunkers = Bunkers(
  relayReqs: RelayReqs(
    relayManager: relayManager,
    eventVerifier: Bip340EventVerifier(),
  ),
  relayPublishes: RelayPublishes(relayManager: relayManager),
  eventSignerFactory: const Bip340EventSignerFactory(),
);

final connection = await bunkers.connectWithBunkerUrl('bunker://...');
final signer = bunkers.createSigner(connection!);
await signer.getPublicKeyAsync();
```

To let the remote signer start, create an invitation with `bunkers.createNostrConnect(relays: [...])`, show its `nostrConnectURL` (as a QR code, for example) and wait for `bunkers.connectWithNostrConnect`. Its key pair comes from the `eventSignerFactory` of `Bunkers`. Pass a `Nip46ClientMetadata` to either flow so the remote signer can name your app and see the permissions it asks for.

Store `connection.toJson()` and rebuild it with `BunkerConnection.fromJson` to restore the session later. `getPublicKey()` is synchronous and throws until the public key is known: call `getPublicKeyAsync()` once, or pass a known key as `cachedPublicKey`.

The remote signer may ask the user to approve each request. While it waits, the request is in `pendingRequests` and `pendingRequestsStream`, and `cancelRequest` drops it. A refusal throws a `SignerRequestRejectedException`. At most `maxConcurrentRequests` requests (100 by default) go out at once. The rest wait in a queue.

## Coming from `ndk`

The classes keep their names, and `package:ndk/ndk.dart` still exports them, now along with `Nip46EventSigner` and `BunkerRequest`. `NostrConnect` no longer generates its own keys: build it with `bunkers.createNostrConnect(relays: ..., clientMetadata: ...)` instead of `NostrConnect(relays: ..., clientMetadata: ...)`. It has `privateKey` and `publicKey` instead of `keyPair`. The deep imports changed package: `package:ndk/data_layer/repositories/signers/nip46_event_signer.dart`, `package:ndk/domain_layer/usecases/bunkers/...` and `package:ndk/domain_layer/entities/nip46_client_metadata.dart` are now `package:ndk_nip46/ndk_nip46.dart`.
