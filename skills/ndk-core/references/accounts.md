# Signers and accounts

## Signers

Every signer implements `EventSigner` from `ndk_signer`.

| Signer | Package |
|--------|---------|
| `Bip340EventSigner(privateKey:, publicKey:)` | `ndk_bip340` |
| `Nip46EventSigner` (bunker) | `ndk_nip46` |
| `Nip07EventSigner` (browser extension) | `ndk_nip07` |
| `Nip55EventSigner` (Android signer app, Flutter) | `ndk_nip55` |

```dart
final signer = Bip340EventSignerFactory().createWithNewKeyPair();
final signed = await signer.sign(
  Nip01Event(pubKey: signer.getPublicKey(), kind: 1, tags: [], content: 'hi'),
);
```

External signers expose `pendingRequests`, `pendingRequestsStream` and `cancelRequest(id)`, and throw `SignerRequestRejectedException` or `SignerRequestCancelledException`.

## Accounts (`ndk_accounts`)

```dart
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';

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
