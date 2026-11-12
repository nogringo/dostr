# dostr_nip44

[NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md) encryption
for Nostr, in pure Dart, with the deprecated
[NIP-04](https://github.com/nostr-protocol/nips/blob/master/04.md) encryption
next to it for the clients and wallets that still need it.

[`dostr_bip340`](https://pub.dev/packages/dostr_bip340) and
[NDK](https://pub.dev/packages/ndk) depend on it: `Bip340EventSigner` encrypts
and decrypts with it. Add it on its own when you encrypt with a private key you
hold yourself.

## Install

```yaml
dependencies:
  dostr_nip44: ^0.1.0
```

## Usage

```dart
import 'package:dostr_nip44/dostr_nip44.dart';

final payload = await Nip44.encryptMessage(
  'hello bob',
  alicePrivateKey,
  bobPublicKey,
);

final plaintext = await Nip44.decryptMessage(
  payload,
  bobPrivateKey,
  alicePublicKey,
);
```

Keys are hex strings. Public keys can be x-only (64 characters, as in Nostr
events) or SEC1 encoded.

## Coming from `ndk` or `dostr_core`

`package:dostr_core/shared/nips/nip44/nip44.dart` and
`package:dostr_core/shared/nips/nip04/nip04.dart` are now both in
`package:dostr_nip44/dostr_nip44.dart`.
