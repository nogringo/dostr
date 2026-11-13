---
icon: lock
label: Encryption (NIP-44)
---

# Encryption (NIP-44)

[`dostr_nip44`](https://pub.dev/packages/dostr_nip44) encrypts and decrypts messages between two keys with [NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md), in pure Dart. It also holds the deprecated [NIP-04](https://github.com/nostr-protocol/nips/blob/master/04.md) encryption, for the clients and wallets that still need it.

```yaml
dependencies:
  dostr_nip44: ^0.1.0
```

## Through a signer

Most apps never call this package. Every `EventSigner` encrypts and decrypts for the account it holds (see [Signers](/concepts/signers.md)), and `Bip340EventSigner` does it with `dostr_nip44`:

```dart
final ciphertext = await signer.encryptNip44(
  plaintext: 'hello bob',
  recipientPubKey: bobPublicKey,
);

final reply = await signer.decryptNip44(
  ciphertext: replyFromBob,
  senderPubKey: bobPublicKey,
);
```

Remote signers (NIP-46, NIP-07, NIP-55) encrypt where the key is, so the same code works with each of them. [Gift wrap](/usecases/gift-wrap.md) encrypts through the signer too. The signer's `encrypt` and `decrypt` are the deprecated NIP-04 ones.

## With a private key

Add the package on its own when you hold the private key yourself:

:::code source="../../packages/nip44/example/dostr_nip44_example.dart" language="dart" range="13-24" title="" :::

- Keys are hex strings. A public key is x-only (64 characters, as in events) or SEC1 encoded.
- `encryptMessage` and `decryptMessage` return futures but do the work on the calling isolate, on every platform.
- The plaintext must be 1 to 65535 bytes: an empty string throws.
- Errors are untyped `Exception`s with a message. `Invalid MAC` means the payload was altered or the keys do not match. The others name a malformed payload or key.
- To skip the key agreement on each message to the same peer, compute the conversation key once with `Nip44.deriveConversationKey(Nip44.computeSharedSecret(privateKey, publicKey))` and pass it as `customConversationKey`. `customNonce` is for test vectors: a nonce must never be reused.

## NIP-04

`Nip04.encrypt(privateKey, publicKey, text)` and `Nip04.decrypt(privateKey, publicKey, text)` are synchronous and take the text last, unlike `Nip44`. The public key must be x-only. NIP-04 is AES-CBC with no MAC, so an altered payload is not detected: use it only for peers that do not support NIP-44. `decrypt` returns an empty string for a payload without `?iv=`.
