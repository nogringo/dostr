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

final accounts = Accounts(const Bip340SignerFactory());

accounts.authStateChanges.listen((account) {
  // null when logged out
});

accounts.loginPrivateKey(privkey: key.privateKey!);
accounts.loginPublicKey(pubkey: otherPubkey); // read-only, now the logged one
accounts.switchAccount(pubkey: key.publicKey);

final signed = await accounts.sign(event);
```

The `LocalSignerFactory` given to `Accounts` builds the signers of `loginPrivateKey` and `loginPublicKey`.
`loginExternalSigner` takes any `NostrSigner`, a [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) bunker included, through the `Bunkers` of [`dostr_nip46`](https://pub.dev/packages/dostr_nip46):

```dart
final signer = bunkers.createSigner(connection);
await signer.getPublicKeyAsync();
accounts.loginExternalSigner(signer: signer);
```

The other external signers log in the same way: a browser extension with [`dostr_nip07`](https://pub.dev/packages/dostr_nip07), an Android signer app with [`dostr_nip55`](https://pub.dev/packages/dostr_nip55).

You can log in several accounts and move between them with `switchAccount(pubkey: ...)`.
`addAccount` adds one without logging it in.
A pubkey is an account only once: adding it again throws an `AccountExistsException`, and switching to an unknown one an `UnknownAccountException`.

`logout` removes the logged account, `removeAccount` any of them.
Nobody is logged in after `logout`, even when other accounts remain.

Each account owns its signer.
Removing the account, or calling `dispose` on `Accounts`, disposes of it, which closes the relay subscription of a NIP-46 bunker.

`sign` throws an `AccountCannotSignException` when nobody is logged in or the logged account is read-only, and an `ArgumentError` for an event whose `pubkey` is not the logged account's.

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

Both emit their current value on subscription, `null` for `authStateChanges` when nobody is logged in.
`accountsStream` then emits an unmodifiable snapshot each time an account is added or removed.
`switchAccount` changes the logged account but not the list, so it only fires `authStateChanges`, and not at all when that account is already the logged one.

`accounts.accounts` is a read-only view of the same data, for a synchronous read.
`getLoggedAccount()`, `isLoggedIn` and `canSign` tell who is logged and whether they can sign.

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

`Accounts` keeps its name and most of its API.
Import it from `package:dostr_accounts/dostr_accounts.dart` instead of `package:ndk/ndk.dart` or the deep import `package:ndk/domain_layer/usecases/accounts/accounts.dart`.
`ndk.accounts.loginWithBunkerUrl`, `loginWithNostrConnect` and `loginWithBunkerConnection` become a `Bunkers` connection and `loginExternalSigner`, as above.

What changed:

| `ndk` | `dostr_accounts` |
|-------|------------------|
| `eventSignerFactory` | `signerFactory` |
| `loginPrivateKey(pubkey: ..., privkey: ...)` | `loginPrivateKey(privkey: ...)`, the pubkey is derived |
| `addAccount(pubkey: ..., type: ..., signer: ...)`, replaced an existing account | `addAccount(signer: ...)`, takes the pubkey of the signer and throws `AccountExistsException` for an existing one |
| `logout()` and `removeAccount()` returned `void` and left the signer open | return a `Future` that completes once the signer is disposed of |
| `dispose()` left the signers open | disposes of every signer |
| `authStateChanges` emitted nothing until the first login | emits `null` on subscription when nobody is logged in |
| a bare `Exception` | `AccountExistsException`, `UnknownAccountException`, `AccountCannotSignException` |
| `sign` signed an event of any pubkey | throws an `ArgumentError` when the event is not the logged account's |
