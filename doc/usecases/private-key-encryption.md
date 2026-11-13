---
icon: key
label: Private key encryption (NIP-49)
---

# Private key encryption (NIP-49)

[`dostr_nip49`](https://pub.dev/packages/dostr_nip49) encrypts a private key with a password into an `ncryptsec` string and decrypts it back ([NIP-49](https://github.com/nostr-protocol/nips/blob/master/49.md)). Use it to store a key at rest or to let a user back it up.

```yaml
dependencies:
  dostr_nip49: ^0.1.0
```

## Example

:::code source="../../packages/nip49/example/dostr_nip49_example.dart" language="dart" range="4-15" title="" :::

The key goes in and comes out as hex: `Nip19.encodePrivateKey` from [`dostr_nip19`](/usecases/bech32.md) turns it into an `nsec`. The password is normalized to NFKC first, as NIP-49 requires.

`keySecurity` records how the key was handled before it was encrypted: `insecure`, `secure`, or `unknown` (the default). It is stored in the `ncryptsec`, and `decrypt` does not return it.

## Cost

scrypt makes each attempt slow on purpose, to slow down password guessing. `logN` sets its cost: 16 by default (`Nip49.defaultLogN`), which takes 64 MiB of memory, and each step up doubles the time and the memory. `encrypt` accepts 1 to 20.

On native platforms scrypt runs in its own isolate. On the web it runs on the main thread and blocks the UI until it is done.

## Errors

- `decrypt` throws `Nip49WrongPasswordException` when the password is wrong, or when the `ncryptsec` was altered.
- A string that is not a valid `ncryptsec` throws a `FormatException`.
- An `ncryptsec` whose `logN` is above `maxLogN` (20 by default, 1 GiB) throws a `RangeError` before any scrypt work. Pass a lower `maxLogN` to `decrypt` on devices with little memory.
- `encrypt` throws an `ArgumentError` when the key is not 32 bytes, and a `RangeError` for a `logN` outside 1 to 20.
