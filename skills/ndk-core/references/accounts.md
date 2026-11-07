# Accounts & Signers

Manage identities via `ndk.accounts`. `Accounts` lives in the `ndk_accounts` package (pure Dart, no `ndk` dependency), which `ndk` re-exports: build one with `Accounts(eventSignerFactory)` to use it without `ndk`.

## Add account

```dart
// Private key
final pubkey = Bip340.getPublicKey(privateKey);
ndk.accounts.addAccount(
  pubkey: pubkey,
  type: AccountType.privateKey,
  signer: ndk.config.eventSignerFactory.create(
    privateKey: privateKey,
    publicKey: pubkey,
  ),
);

// Read-only (public key only)
ndk.accounts.addAccount(
  pubkey: pubkey,
  type: AccountType.publicKey,
  signer: ndk.config.eventSignerFactory.create(
    privateKey: null,
    publicKey: pubkey,
  ),
);

// External signer (NIP-46, NIP-07, Amber — see ndk-flutter skill)
ndk.accounts.addAccount(
  pubkey: pubkey,
  type: AccountType.externalSigner,
  signer: yourExternalSigner,
);
```

## Switch active account

```dart
ndk.accounts.switchAccount(pubkey: pubkey);
```

## Query accounts

```dart
ndk.accounts.accounts          // Map<String, Account>
ndk.accounts.getPublicKey()    // String? — active account pubkey
ndk.accounts.hasAccount(pubkey) // bool
```

## Account types

| `AccountType` | Description |
| ------------- | ----------- |
| `privateKey` | Full signing capability |
| `publicKey` | Read-only, no signing |
| `externalSigner` | Delegates signing to external app/extension |

## Built-in signers (Dart-only)

```dart
// BIP-340 (schnorr) — default
Bip340EventSignerFactory().create(privateKey: nsec, publicKey: npub)

// Rust verifier from ndk_rust_verifier, faster verification (requires native toolchain)
RustEventVerifier()

// Pure Dart verifier
Bip340EventVerifier()
```

## NIP-07 / Amber / NIP-46 signers

`Nip07EventSigner` lives in the `ndk_nip07` package (pure Dart, web only, no `ndk` or Flutter dependency). `Nip55EventSigner` and `Nip55Signer` live in the `ndk_nip55` package (Flutter plugin, Android only, no `ndk` or `ndk_flutter` dependency). `ndk_flutter` exports both. See [[ndk-flutter]] accounts reference.

## Bunkers (NIP-46)

`Bunkers`, `Nip46EventSigner`, `BunkerConnection` and `NostrConnect` live in the `ndk_nip46` package (pure Dart, on top of `ndk_core`, no `ndk` dependency). `ndk` re-exports it.

```dart
// Connect to remote signer
final connection = await ndk.bunkers.connectWithBunkerUrl('bunker://...');

// Or parse connection from string
final conn = BunkerConnection.fromJson(jsonString);
final signer = Nip46EventSigner(
  connection: conn,
  relayReqs: ndk.relayReqs,
  relayPublishes: ndk.relayPublishes,
  eventSignerFactory: ndk.config.eventSignerFactory,
);
```
