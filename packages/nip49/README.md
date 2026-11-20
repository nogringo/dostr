# dostr_nip49

[NIP-49](https://github.com/nostr-protocol/nips/blob/master/49.md) private key encryption for Nostr: encrypt a private key with a password into an `ncryptsec` string, and decrypt it back.

Pure Dart, no relay or network code. scrypt runs in its own isolate on native platforms.
On web it runs on the main thread and blocks the UI while it runs.
scrypt and XChaCha20-Poly1305 are implemented here, so the only dependencies are `crypto` and `unorm_dart`.

## Install

```yaml
dependencies:
  dostr_nip49: ^0.1.0
```

## Usage

```dart
import 'package:dostr_nip49/dostr_nip49.dart';

final ncryptsec = await Ncryptsec.encrypt(
  '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683',
  'password',
);
final encoded = ncryptsec.encode();

final privateKey = await Ncryptsec.decode(encoded).decrypt('password');
```

The key goes in and comes out as hex: `Nsec(privateKey).encode()` from [`dostr_nip19`](https://pub.dev/packages/dostr_nip19) turns it into an `nsec`.
The password is normalized to NFKC first, as NIP-49 requires.

`decode` ignores whitespace around the input, and `tryDecode` returns null where `decode` throws.
An `Ncryptsec` is a value: two with the same bytes are equal, and `toString` leaves the encrypted key out.

`keySecurity` records how the key was handled before it was encrypted: `insecure`, `secure`, or `unknown` (the default).
`logN` and `keySecurity` can be read before `decrypt`, without the password, for example to warn about a slow decryption or a key that was once stored unencrypted.
Only `decrypt` checks them: it fails with `Nip49WrongPasswordException` when either was altered.

## Cost

scrypt makes each attempt slow on purpose, to slow down password guessing.
`logN` sets its cost: 16 by default (`Ncryptsec.defaultLogN`), which takes 64 MiB of memory, and each step up doubles the time and the memory.
`encrypt` accepts 1 to 20 (`Ncryptsec.maxLogN`).

## Errors

- `decode` throws a `FormatException` when the input is not valid bech32, has another prefix, is not 91 bytes, or holds an unknown version, a `logN` of 0 or an unknown key security byte. No message quotes the input, since it may be an `nsec` pasted in the wrong field.
- `decrypt` throws a `Nip49Exception`, which is sealed:
  - `Nip49WrongPasswordException` when the password is wrong, or when the `ncryptsec` was altered.
  - `Nip49CostTooHighException` when `logN` is above `maxLogN` (20 by default, 1 GiB), before any scrypt work. Its `logN` and `maxLogN` say by how much. Pass a lower `maxLogN` to `decrypt` on devices with little memory.
- `encrypt` throws an `ArgumentError` when the key is not 32 bytes of hex, without quoting it, and a `RangeError` for a `logN` outside 1 to 20.

## Coming from `ndk`

`package:ndk/shared/nips/nip49/nip49.dart` is now `package:dostr_nip49/dostr_nip49.dart`.
The static `Nip49` class is gone:

| `ndk` | `dostr_nip49` |
| --- | --- |
| `await Nip49.encrypt(key, password)` | `(await Ncryptsec.encrypt(key, password)).encode()` |
| `await Nip49.decrypt(ncryptsec, password)` | `await Ncryptsec.decode(ncryptsec).decrypt(password)` |
| `Nip49.defaultLogN`, `Nip49.maxLogN` | `Ncryptsec.defaultLogN`, `Ncryptsec.maxLogN` |
| `SecretBoxAuthenticationError` from `cryptography` | `Nip49WrongPasswordException` |
| `RangeError` for a `logN` above `maxLogN` | `Nip49CostTooHighException` |
| `bech32` exceptions, or a `RangeError` for a `logN` of 0 | `FormatException` from `decode` |
| `FormatException` from `encrypt` for a key that is not hex | `ArgumentError` |
