# ndk_nip49

[NIP-49](https://github.com/nostr-protocol/nips/blob/master/49.md) private key
encryption for Nostr: encrypt a private key with a password into an
`ncryptsec` string, and decrypt it back.

Pure Dart, no relay or network code. scrypt runs in its own isolate on native
platforms. On web it runs on the main thread and blocks the UI while it runs.

[NDK](https://pub.dev/packages/ndk) depends on it and exports it, so apps that
already use `ndk` don't need to add it.

## Install

```yaml
dependencies:
  ndk_nip49: ^0.1.0
```

## Usage

```dart
import 'package:ndk_nip49/ndk_nip49.dart';

final ncryptsec = await Nip49.encrypt(
  '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683',
  'password',
);
final privateKey = await Nip49.decrypt(ncryptsec, 'password');
```

`logN` sets the scrypt cost: 16 by default (64 MiB of memory), and `decrypt`
rejects anything above `maxLogN` (20, 1 GiB) before doing any work. A wrong
password throws `Nip49WrongPasswordException`, and a string that is not a
valid `ncryptsec` throws a `FormatException`.

## Coming from `ndk`

`package:ndk/shared/nips/nip49/nip49.dart` is now
`package:ndk_nip49/ndk_nip49.dart`. `package:ndk/ndk.dart` still exports
`Nip49` and `Nip49KeySecurity`, along with `Nip49WrongPasswordException`.
`decrypt` throws it instead of `SecretBoxAuthenticationError` from
`cryptography`, and wraps the `bech32` decoding errors in a `FormatException`.
