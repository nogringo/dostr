# dostr_nip46

[NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) remote signing for Nostr: connect to a bunker with a `bunker://` URL, or let it connect to you with a `nostrconnect://` URL, then sign events and encrypt or decrypt NIP-04 and NIP-44 messages through it.

It implements the `NostrSigner` of [`dostr_signer`](https://pub.dev/packages/dostr_signer), so Dostr accounts can use it.
It runs on [`dostr_core`](https://pub.dev/packages/dostr_core).

## Standalone

```yaml
dependencies:
  dostr_nip46: ^0.1.0
  dostr_core: ^0.1.0
  dostr_bip340: ^0.1.0
```

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip46/dostr_nip46.dart';

final relayManager = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
);
final bunkers = Bunkers(
  relayReqs: RelayReqs(
    relayManager: relayManager,
    eventVerifier: Bip340EventVerifier(),
  ),
  relayPublishes: RelayPublishes(relayManager: relayManager),
  signerFactory: const Bip340SignerFactory(),
);

final connection = await bunkers.connectWithBunkerUrl(
  'bunker://...',
  authCallback: (url) => print('approve at $url'),
);
final signer = await bunkers.createSigner(connection);
```

Log the signer in with `accounts.loginExternalSigner(signer: signer)`, where `accounts` is an `Accounts` from [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).
`connectWithBunkerUrl` throws a `SignerRequestRejectedException` when the bunker refuses, and a `SignerRequestFailedException` when no relay takes the request or the bunker accepts nothing within `timeout` (10 minutes by default).
`authCallback` only gets https urls: a `bunker://` url can come from anyone, and the challenge often goes straight to a launcher.
`createSigner` asks the bunker for the user's pubkey, which the bunker may ask the user to approve first, and completes once it has it: `publicKey` never throws.

## Nostr Connect

To let the remote signer start, create a `nostrconnect://` invitation, show its url (as a QR code, for example) and wait:

```dart
final nostrConnect = bunkers.createNostrConnect(
  relays: [RelayUrl.parse('wss://relay.example.com')],
  clientMetadata: clientMetadata,
);
print(nostrConnect.nostrConnectURL);

final connection = await bunkers.connectWithNostrConnect(nostrConnect);
```

Its key pair comes from the `signerFactory` of `Bunkers`.
`connectWithNostrConnect` throws a `SignerRequestFailedException` when no remote signer accepts within `timeout`.

## Client metadata

Pass the same `Nip46ClientMetadata` to both flows, as `clientMetadata`.
A `bunker://` url does not identify your app, so this metadata is the only way for the remote signer to label the connection and see the permissions it asks for:

```dart
const clientMetadata = Nip46ClientMetadata(
  name: 'My app',
  url: 'https://myapp.example',
  perms: ['sign_event:1', 'nip44_encrypt'],
);
```

## Restoring a connection

Store the `BunkerConnection` to re-establish the connection in future sessions: `connection.toJson()` serializes it and `BunkerConnection.fromJson()` restores it.
Without it, users have to connect again each time.
Keep it in secure storage, as you would a private key: whoever holds it can send the bunker requests under the permissions the user granted.

```dart
final signer = await bunkers.createSigner(BunkerConnection.fromJson(stored));
accounts.loginExternalSigner(signer: signer);
```

Store the user's pubkey too, and `Nip46Signer(connection: ..., publicKey: ...)` restores the signer without asking the bunker again.

NIP-46 lets the remote signer pick the relays.
Call `switchRelays()` right after connecting, before other requests, and store the connection again when it returns relays:

```dart
final relays = await signer.switchRelays();
if (relays != null) {
  // store signer.connection again
}
```

An older bunker may ignore `switch_relays`: like `ping()`, it then throws a `SignerRequestFailedException` once `timeout` passes (10 seconds by default).

## Pending requests

The remote signer may ask the user to approve each request.
While it waits, the request is in `pendingRequests` and `pendingRequestsStream`, and `cancelRequest` drops it.
A refusal throws a `SignerRequestRejectedException`, and an answer the signer cannot use, such as an event signed by another pubkey, a `SignerRequestFailedException`.
A request that every relay refuses or never gets also fails with a `SignerRequestFailedException`, at once.
Give the signer a `verifier`, such as a `Bip340EventVerifier`, to also check the signature of every event the bunker signs.
At most `maxConcurrentRequests` requests (100 by default) go out at once.
The rest wait in a queue.

## Logging out

`logout()` tells the bunker the session is over, then disposes the signer.
It returns whether the bunker acknowledged.
A `dispose()` meanwhile waits for it, so an `Accounts` can remove the account right away.
Delete the stored `BunkerConnection` either way: NIP-46 makes `logout` a courtesy, and the bunker may still accept requests from its key.

## Coming from `ndk`

`Nip46EventSigner` is now `Nip46Signer`, and `Bunkers` takes its factory as `signerFactory` instead of `eventSignerFactory`.
The other classes keep their names.
Import them from `package:dostr_nip46/dostr_nip46.dart` instead of `package:ndk/ndk.dart`: it also exports `Nip46Signer` and `BunkerRequest`.
`NostrConnect` no longer generates its own keys: build it with `bunkers.createNostrConnect(relays: ..., clientMetadata: ...)` instead of `NostrConnect(relays: ..., clientMetadata: ...)`.
It has `privateKey` and `publicKey` instead of `keyPair`.
`connectWithBunkerUrl` and `connectWithNostrConnect` return a `BunkerConnection` and throw when they get none, instead of returning null, and `connectWithNostrConnect` takes no `authCallback`.
The deep imports changed package: `package:ndk/data_layer/repositories/signers/nip46_event_signer.dart`, `package:ndk/domain_layer/usecases/bunkers/...` and `package:ndk/domain_layer/entities/nip46_client_metadata.dart` are now `package:dostr_nip46/dostr_nip46.dart`.
