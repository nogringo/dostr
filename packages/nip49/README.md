# dostr_nip49

[NIP-49](https://github.com/nostr-protocol/nips/blob/master/49.md) private key
encryption for Nostr: encrypt a private key with a password into an
`ncryptsec` string, and decrypt it back.

Pure Dart, no relay or network code. scrypt runs in its own isolate on native
platforms. On web it runs on the main thread and blocks the UI while it runs.

## Install

```yaml
dependencies:
  dostr_nip49: ^0.1.0
```

## Usage

```dart
import 'package:dostr_nip49/dostr_nip49.dart';

final ncryptsec = await Nip49.encrypt(
  '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683',
  'password',
);
final privateKey = await Nip49.decrypt(ncryptsec, 'password');
```

The key goes in and comes out as hex: `Nsec(privateKey).encode()` from
[`dostr_nip19`](https://pub.dev/packages/dostr_nip19) turns it into an `nsec`.
The password is normalized to NFKC first, as NIP-49 requires.

`keySecurity` records how the key was handled before it was encrypted:
`insecure`, `secure`, or `unknown` (the default). It is stored in the
`ncryptsec`, and `decrypt` does not return it.

## Cost

scrypt makes each attempt slow on purpose, to slow down password guessing.
`logN` sets its cost: 16 by default (`Nip49.defaultLogN`), which takes 64 MiB
of memory, and each step up doubles the time and the memory. `encrypt` accepts
1 to 20.

## Errors

- `decrypt` throws `Nip49WrongPasswordException` when the password is wrong, or
  when the `ncryptsec` was altered.
- A string that is not a valid `ncryptsec` throws a `FormatException`.
- An `ncryptsec` whose `logN` is above `maxLogN` (20 by default, 1 GiB) throws a
  `RangeError` before any scrypt work. Pass a lower `maxLogN` to `decrypt` on
  devices with little memory.
- `encrypt` throws an `ArgumentError` when the key is not 32 bytes, and a
  `RangeError` for a `logN` outside 1 to 20.

## Coming from `ndk`

`package:ndk/shared/nips/nip49/nip49.dart` is now
`package:dostr_nip49/dostr_nip49.dart`, which exports `Nip49` and
`Nip49KeySecurity`, along with `Nip49WrongPasswordException`. `decrypt` throws
it instead of `SecretBoxAuthenticationError` from `cryptography`, and wraps the
`bech32` decoding errors in a `FormatException`.
