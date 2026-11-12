---
icon: person
---

# Accounts

[`ndk_accounts`](https://pub.dev/packages/ndk_accounts) keeps the accounts an app logs in with: a private key, a public key (read-only) or an external signer such as a NIP-46 bunker or a NIP-07 browser extension. It switches between them and signs as the logged one.

```yaml
dependencies:
  ndk_accounts: ^0.1.0
  ndk_bip340: ^0.1.0
```

## Example

:::code source="../../packages/accounts/example/ndk_accounts_example.dart" language="dart" range="5-33" title="" :::

The `LocalEventSignerFactory` given to `Accounts` builds the signers of `loginPrivateKey` and `loginPublicKey`. `loginExternalSigner` takes any `EventSigner`.

You can log in several accounts and move between them with `switchAccount(pubkey: ...)`. `logout` removes the logged one, `removeAccount` any of them.

## Relay authentication

`Accounts` implements `AuthAccounts` from [`ndk_signer`](https://pub.dev/packages/ndk_signer). Give it to the `RelayManager` of [`ndk_core`](https://pub.dev/packages/ndk_core), with an `AuthHandler`, and relays that ask for NIP-42 authentication get the logged account where the handler agrees:

```dart
final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  accounts: accounts,
  authHandler: (url, pubkey) async => url == 'wss://relay.example.com',
);
```

See [NIP-42 authentication](/concepts/nip42-auth.md).

## Reacting to changes

```dart watch the logged in account
accounts.authStateChanges.listen((account) {
  // null when logged out
});
```

```dart watch the list of accounts
accounts.accountsStream.listen((accounts) {
  // pubkey -> Account, emitted on every add and remove
});
```

`accountsStream` emits the current accounts on subscription, then an unmodifiable snapshot each time an account is added or removed. `switchAccount` changes the logged account but not the list, so it only fires `authStateChanges`.

`accounts.accounts` is a read-only view of the same data, for a synchronous read. `getLoggedAccount()`, `isLoggedIn` and `canSign` tell who is logged and whether they can sign.

## Browser extension (NIP-07)

[`ndk_nip07`](https://pub.dev/packages/ndk_nip07) signs with the user's browser extension through `window.nostr`. It only signs on the web: elsewhere `canSign()` returns `false`.

:::code source="../../packages/nip07/example/ndk_nip07_example.dart" language="dart" range="3-12" title="" :::

Then log it in:

```dart
accounts.loginExternalSigner(signer: signer);
```

`getPublicKey()` is synchronous and throws until the public key is known. Call `getPublicKeyAsync()` once, or pass a known key as `Nip07EventSigner(cachedPublicKey: pubkey)` when restoring an account.

## Remote signer (NIP-46)

[`ndk_nip46`](https://pub.dev/packages/ndk_nip46) talks to a bunker over relays, through `ndk_core`:

```yaml
dependencies:
  ndk_nip46: ^0.1.0
  ndk_core: ^0.11.0-dev.2
```

:::code source="../../packages/nip46/example/ndk_nip46_example.dart" language="dart" range="7-23" title="bunker url" :::

```dart log in
final signer = bunkers.createSigner(connection!);
await signer.getPublicKeyAsync();
accounts.loginExternalSigner(signer: signer);
```

To let the remote signer start, create a `nostrconnect://` invitation, show its url (as a QR code, for example) and wait:

```dart nostr connect
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

Pass the same `Nip46ClientMetadata` to both flows. A `bunker://` url does not identify your app, so this metadata is the only way for the remote signer to label the connection:

```dart client metadata
const clientMetadata = Nip46ClientMetadata(
  name: 'My app',
  url: 'https://myapp.example',
  perms: ['sign_event:1', 'nip44_encrypt'],
);
```

!!!warning Important
Store the `BunkerConnection` to re-establish the connection in future sessions: `connection.toJson()` serializes it and `BunkerConnection.fromJson()` restores it. Without it, users have to connect again each time.
!!!

```dart restore a connection
final signer = bunkers.createSigner(BunkerConnection.fromJson(stored));
await signer.getPublicKeyAsync();
accounts.loginExternalSigner(signer: signer);
```

NIP-46 lets the remote signer pick the relays. Call `switchRelays()` right after connecting, before other requests, and store the connection again when it returns relays:

```dart switch relays
final relays = await signer.switchRelays();
if (relays != null) {
  // store signer.connection again
}
```

External signers wait for the user to approve each request. See [signers](/concepts/signers.md) for their pending requests, and for cancelling or catching a refusal.
