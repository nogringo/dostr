# ndk_accounts

The accounts of [NDK](https://pub.dev/packages/ndk): log in with a private key, a public key, an external signer or a [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) bunker, switch between the logged accounts, and sign as the current one. It does not depend on `ndk`.

`Accounts` implements `AuthAccounts` from [`ndk_signer`](https://pub.dev/packages/ndk_signer), so relays (NIP-42) and Blossom servers authenticate as its accounts.

## With NDK

`ndk` depends on this package, re-exports it and exposes it as `ndk.accounts`:

```dart
import 'package:ndk/ndk.dart';

ndk.accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
ndk.broadcast.broadcast(nostrEvent: event); // signed by the logged account
```

## Standalone

```yaml
dependencies:
  ndk_accounts: ^0.1.0
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';

final accounts = Accounts(const Bip340EventSignerFactory());

accounts.authStateChanges.listen((account) {
  // null when logged out
});

accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
accounts.loginPublicKey(pubkey: otherPubkey); // read-only, now the logged one
accounts.switchAccount(pubkey: key.publicKey);

final signed = await accounts.sign(event);
```

The `LocalEventSignerFactory` given to `Accounts` builds the signers of `loginPrivateKey` and `loginPublicKey`. `loginExternalSigner` takes any `EventSigner`, a [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) bunker included, through the `Bunkers` of [`ndk_nip46`](https://pub.dev/packages/ndk_nip46):

```dart
final signer = bunkers.createSigner(connection);
await signer.getPublicKeyAsync();
accounts.loginExternalSigner(signer: signer);
```

With `ndk`, `ndk.accounts.loginWithBunkerUrl`, `loginWithNostrConnect` and `loginWithBunkerConnection` do it for you.

`accountsStream` emits the known accounts on subscription, then an unmodifiable snapshot every time one is added or removed. `authStateChanges` emits the logged account, or null, every time it changes.

More in [example/](example/) and the [accounts docs](https://dart-nostr.com/usecases/accounts/).

## Coming from `ndk`

`Accounts` keeps its name and its API, and `package:ndk/ndk.dart` still exports it. The deep import `package:ndk/domain_layer/usecases/accounts/accounts.dart` is now `package:ndk_accounts/ndk_accounts.dart`.
