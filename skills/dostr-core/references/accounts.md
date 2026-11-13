# Signers and accounts

## Signers

Every signer implements `EventSigner` from `dostr_signer`.

| Signer | Package |
|--------|---------|
| `Bip340EventSigner(privateKey:, publicKey:)` | `dostr_bip340` |
| `Nip46EventSigner` (bunker) | `dostr_nip46` |
| `Nip07EventSigner` (browser extension) | `dostr_nip07` |
| `Nip55EventSigner` (Android signer app, Flutter) | `dostr_nip55` |

```dart
final signer = Bip340EventSignerFactory().createWithNewKeyPair();
final signed = await signer.sign(
  Nip01Event(pubKey: signer.getPublicKey(), kind: 1, tags: [], content: 'hi'),
);
```

External signers expose `pendingRequests`, `pendingRequestsStream` and `cancelRequest(id)`, and throw `SignerRequestRejectedException` or `SignerRequestCancelledException`.

## Accounts (`dostr_accounts`)

```dart
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';

final accounts = Accounts(const Bip340EventSignerFactory());

accounts.loginPrivateKey(pubkey: pubkey, privkey: privkey);
accounts.loginPublicKey(pubkey: otherPubkey); // read-only
accounts.loginExternalSigner(signer: nip46Signer);
accounts.switchAccount(pubkey: pubkey);
accounts.logout();

final signed = await accounts.sign(event);
accounts.authStateChanges.listen((account) {}); // null when logged out
accounts.accountsStream.listen((all) {});
```

Pass `accounts` to `RelayManager(accounts: ..., authHandler: ...)` so relays asking for NIP-42 authentication can be answered as the logged account.
