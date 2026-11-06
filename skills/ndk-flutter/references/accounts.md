# Account State Management

## Save / Restore

Persists accounts to `FlutterSecureStorage`. Call on auth state change and app start.

```dart
// Call before runApp — reads storage, adds signers to ndk
await ndkFlutter.restoreAccountsState();

// Call after every login/logout/account switch
await ndkFlutter.saveAccountsState();
```

## Supported account kinds

| Kind | `AccountKinds` value | Signer class | Notes |
| ---- | -------------------- | ------------ | ----- |
| Private key | `privkey` | internal factory | nsec stored encrypted |
| Public key (read-only) | `pubkey` | internal factory | no signing |
| NIP-07 browser ext | `nip07` | `Nip07EventSigner` | web only, from `ndk_nip07` |
| NIP-55 signer app | `nip55` | `Nip55EventSigner` | Android only, from `ndk_nip55` |
| NIP-46 bunker | `bunker` | `Nip46EventSigner` | remote signer, from `ndk_nip46` |

## Available signers

```dart
import 'package:ndk_flutter/ndk_flutter.dart';

// NIP-07 (browser extension, web), from ndk_nip07 and exported by ndk_flutter
final signer = Nip07EventSigner(cachedPublicKey: pubkey);

// NIP-55 signer app (Android), from ndk_nip55 and exported by ndk_flutter
final login = await const Nip55Signer().login();
final signer = Nip55EventSigner(
  publicKey: login!.pubkey,
  nip55Signer: Nip55Signer(package: login.package),
);

// NIP-46 bunker
final signer = Nip46EventSigner(
  connection: BunkerConnection.fromJson(jsonDecode(connectionJson)),
  relayReqs: ndk.relayReqs,
  relayPublishes: ndk.relayPublishes,
  eventSignerFactory: ndk.config.eventSignerFactory,
  cachedPublicKey: pubkey,
);
```

## Add account manually

```dart
ndk.accounts.addAccount(
  pubkey: pubkey,
  type: AccountType.externalSigner, // or .privateKey / .publicKey
  signer: signer,
);

// Switch active account
ndk.accounts.switchAccount(pubkey: pubkey);
```

## Utility methods on NdkFlutter

```dart
// Format npub for display (truncated)
final display = ndkFlutter.formatNpub(pubkey);
// → "npub1abcde1234…5678"

// Deterministic color from pubkey (for avatars)
final color = NdkFlutter.getColorFromPubkey(pubkey);

// Resolve NIP-05 identifier
final result = await NdkFlutter.fetchNip05('user@domain.com');
if (result.pubkey != null) { /* verified */ }
```
