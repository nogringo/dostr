## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - A new API replaces the static `Nip49` class of `ndk`. `Ncryptsec.encrypt` returns an `Ncryptsec`, which `encode` turns into a string, and `Ncryptsec.decode` and `tryDecode` read one back, so that `logN` and `keySecurity` can be read without the password before `decrypt`. The README maps each `ndk` call to its replacement.
 - `decode` ignores whitespace around the input, and throws only a `FormatException`, whose message never quotes the input, which may be an `nsec` pasted in the wrong field. In `ndk`, `Nip49.decrypt` threw the `bech32` exceptions, a `RangeError` for a `logN` of 0, and a `FormatException` that quoted the input.
 - `decrypt` throws a `Nip49Exception`, which is sealed: `Nip49WrongPasswordException` for a wrong password or an altered `ncryptsec`, and `Nip49CostTooHighException`, with the `logN` and the `maxLogN`, for a `logN` above `maxLogN`. In `ndk`, it threw a `SecretBoxAuthenticationError` from `cryptography` and a `RangeError`.
 - `encrypt` throws an `ArgumentError` that does not quote the key when it is not 32 bytes of hex. In `ndk`, the error quoted the key, and a key that was not hex threw a `FormatException`.
 - `Ncryptsec` is a value, with `==` and `hashCode`, and `toString` leaves the encrypted key out.
 - XChaCha20-Poly1305 is implemented here, tested against the vectors of RFC 8439 and draft-irtf-cfrg-xchacha, so this package does not depend on `cryptography`. Its only dependencies are `crypto` and `unorm_dart`.
