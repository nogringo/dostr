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

`accountsStream` emits the known accounts on subscription, then an unmodifiable snapshot every time one is added or removed. `authStateChanges` emits the logged account, or null, every time it changes.

More in [example/](example/) and the [accounts docs](https://nogringo.github.io/dostr/usecases/accounts/).

## Coming from `ndk`

`Accounts` keeps its name and its API. Import it from `package:dostr_accounts/dostr_accounts.dart` instead of `package:ndk/ndk.dart` or the deep import `package:ndk/domain_layer/usecases/accounts/accounts.dart`. `ndk.accounts.loginWithBunkerUrl`, `loginWithNostrConnect` and `loginWithBunkerConnection` become a `Bunkers` connection and `loginExternalSigner`, as above.
