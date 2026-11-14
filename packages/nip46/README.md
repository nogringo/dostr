# dostr_nip46

[NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) remote signing for Nostr: connect to a bunker with a `bunker://` URL, or let it connect to you with a `nostrconnect://` URL, then sign events and encrypt or decrypt NIP-04 and NIP-44 messages through it.

It implements the `EventSigner` of [`dostr_signer`](https://pub.dev/packages/dostr_signer), so Dostr accounts can use it. It runs on [`dostr_core`](https://pub.dev/packages/dostr_core).

## Standalone

```yaml
dependencies:
  dostr_nip46: ^0.1.0
  dostr_core: ^0.11.0-dev.2
  dostr_bip340: ^0.1.0
```

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip46/dostr_nip46.dart';

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

Log the signer in with `accounts.loginExternalSigner(signer: signer)`, where `accounts` is an `Accounts` from [`dostr_accounts`](https://pub.dev/packages/dostr_accounts). `getPublicKey()` is synchronous and throws until the public key is known: call `getPublicKeyAsync()` once, or pass a known key as `cachedPublicKey`.

## Nostr Connect

To let the remote signer start, create a `nostrconnect://` invitation, show its url (as a QR code, for example) and wait:

```dart
final nostrConnect = bunkers.createNostrConnect(
  relays: ['wss://relay.example.com'],
  clientMetadata: clientMetadata,
);
print(nostrConnect.nostrConnectURL);

final connection = await bunkers.connectWithNostrConnect(
  nostrConnect,
  authCallback: (url) => print('approve at $url'),
);
```

Its key pair comes from the `eventSignerFactory` of `Bunkers`.

## Client metadata

Pass the same `Nip46ClientMetadata` to both flows, as `clientMetadata`. A `bunker://` url does not identify your app, so this metadata is the only way for the remote signer to label the connection and see the permissions it asks for:

```dart
const clientMetadata = Nip46ClientMetadata(
  name: 'My app',
  url: 'https://myapp.example',
  perms: ['sign_event:1', 'nip44_encrypt'],
);
```

## Restoring a connection

Store the `BunkerConnection` to re-establish the connection in future sessions: `connection.toJson()` serializes it and `BunkerConnection.fromJson()` restores it. Without it, users have to connect again each time.

```dart
final signer = bunkers.createSigner(BunkerConnection.fromJson(stored));
await signer.getPublicKeyAsync();
accounts.loginExternalSigner(signer: signer);
```

NIP-46 lets the remote signer pick the relays. Call `switchRelays()` right after connecting, before other requests, and store the connection again when it returns relays:

```dart
final relays = await signer.switchRelays();
if (relays != null) {
  // store signer.connection again
}
```

## Pending requests

The remote signer may ask the user to approve each request. While it waits, the request is in `pendingRequests` and `pendingRequestsStream`, and `cancelRequest` drops it. A refusal throws a `SignerRequestRejectedException`. At most `maxConcurrentRequests` requests (100 by default) go out at once. The rest wait in a queue.

## Coming from `ndk`

The classes keep their names. Import them from `package:dostr_nip46/dostr_nip46.dart` instead of `package:ndk/ndk.dart`: it also exports `Nip46EventSigner` and `BunkerRequest`. `NostrConnect` no longer generates its own keys: build it with `bunkers.createNostrConnect(relays: ..., clientMetadata: ...)` instead of `NostrConnect(relays: ..., clientMetadata: ...)`. It has `privateKey` and `publicKey` instead of `keyPair`. The deep imports changed package: `package:ndk/data_layer/repositories/signers/nip46_event_signer.dart`, `package:ndk/domain_layer/usecases/bunkers/...` and `package:ndk/domain_layer/entities/nip46_client_metadata.dart` are now `package:dostr_nip46/dostr_nip46.dart`.
