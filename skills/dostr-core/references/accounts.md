# Signers and accounts

## Signers

Every signer implements `NostrSigner` from `dostr_signer`.

| Signer | Package |
|--------|---------|
| `Bip340Signer(privateKey:, publicKey:)` | `dostr_bip340` |
| `Nip46Signer` (bunker) | `dostr_nip46` |
| `Nip07Signer` (browser extension) | `dostr_nip07` |
| `Nip55Signer` (Android signer app, Flutter) | `dostr_nip55` |

```dart
final signer = Bip340SignerFactory().createWithNewKeyPair();
final signed = await signer.sign(
  Nip01Event(pubkey: signer.publicKey, kind: 1, tags: [], content: 'hi'),
);
```

External signers expose `pendingRequests`, `pendingRequestsStream` and `cancelRequest(id)`, and throw `SignerRequestRejectedException` or `SignerRequestCancelledException`, both a `SignerRequestException`.

## Accounts (`dostr_accounts`)

```dart
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';

final accounts = Accounts(const Bip340SignerFactory());

accounts.loginPrivateKey(privkey: privkey); // derives the pubkey
accounts.loginPublicKey(pubkey: otherPubkey); // read-only
accounts.loginExternalSigner(signer: nip46Signer);
accounts.switchAccount(pubkey: pubkey);
await accounts.logout(); // disposes of the signer

final signed = await accounts.sign(event);
accounts.authStateChanges.listen((account) {}); // null when logged out
accounts.accountsStream.listen((all) {});
```

Pass `accounts` to `RelayManager(accounts: ..., authHandler: ...)` so relays asking for NIP-42 authentication can be answered as the logged account.
