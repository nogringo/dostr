# dostr_accounts

Accounts for Nostr apps: log in with a private key, a public key, an external signer or a [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) bunker, switch between the logged accounts, and sign as the current one.

`Accounts` implements `AuthAccounts` from [`dostr_signer`](https://pub.dev/packages/dostr_signer), so relays (NIP-42) and Blossom servers authenticate as its accounts.

## Standalone

```yaml
dependencies:
  dostr_accounts: ^0.1.0
  dostr_bip340: ^0.1.0
```

```dart
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';

final accounts = Accounts(const Bip340EventSignerFactory());

accounts.authStateChanges.listen((account) {
  // null when logged out
});

accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
accounts.loginPublicKey(pubkey: otherPubkey); // read-only, now the logged one
accounts.switchAccount(pubkey: key.publicKey);

final signed = await accounts.sign(event);
```

The `LocalEventSignerFactory` given to `Accounts` builds the signers of `loginPrivateKey` and `loginPublicKey`. `loginExternalSigner` takes any `EventSigner`, a [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) bunker included, through the `Bunkers` of [`dostr_nip46`](https://pub.dev/packages/dostr_nip46):

```dart
final signer = bunkers.createSigner(connection);
await signer.getPublicKeyAsync();
accounts.loginExternalSigner(signer: signer);
```

The other external signers log in the same way: a browser extension with [`dostr_nip07`](https://pub.dev/packages/dostr_nip07), an Android signer app with [`dostr_nip55`](https://pub.dev/packages/dostr_nip55).

You can log in several accounts and move between them with `switchAccount(pubkey: ...)`. `logout` removes the logged one, `removeAccount` any of them.

More in [example/](example/).

## Reacting to changes

```dart
accounts.authStateChanges.listen((account) {
  // the logged account, null when logged out
});

accounts.accountsStream.listen((accounts) {
  // pubkey -> Account, emitted on every add and remove
});
```

`accountsStream` emits the current accounts on subscription, then an unmodifiable snapshot each time an account is added or removed. `switchAccount` changes the logged account but not the list, so it only fires `authStateChanges`.

`accounts.accounts` is a read-only view of the same data, for a synchronous read. `getLoggedAccount()`, `isLoggedIn` and `canSign` tell who is logged and whether they can sign.

## Relay authentication

Give `Accounts` to the `RelayManager` of [`dostr_core`](https://pub.dev/packages/dostr_core), with an `AuthHandler`, and relays that ask for NIP-42 authentication get the logged account where the handler agrees:

```dart
final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  accounts: accounts,
  authHandler: (url, pubkey) async => url == 'wss://relay.example.com',
);
```

See the [NIP-42 authentication](https://pub.dev/packages/dostr_core#nip-42-authentication) of `dostr_core`.

## Coming from `ndk`

`Accounts` keeps its name and its API. Import it from `package:dostr_accounts/dostr_accounts.dart` instead of `package:ndk/ndk.dart` or the deep import `package:ndk/domain_layer/usecases/accounts/accounts.dart`. `ndk.accounts.loginWithBunkerUrl`, `loginWithNostrConnect` and `loginWithBunkerConnection` become a `Bunkers` connection and `loginExternalSigner`, as above.
