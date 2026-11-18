# dostr_nip44

[NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md) encryption for Nostr, in pure Dart, with the deprecated [NIP-04](https://github.com/nostr-protocol/nips/blob/master/04.md) encryption next to it for the clients and wallets that still need it.

[`dostr_bip340`](https://pub.dev/packages/dostr_bip340) depends on it: `Bip340Signer` encrypts and decrypts with it.
Add it on its own when you encrypt with a private key you hold yourself.

## Install

```yaml
dependencies:
  dostr_nip44: ^0.1.0
```

## Usage

```dart
import 'package:dostr_nip44/dostr_nip44.dart';

final payload = Nip44.encryptMessage(
  'hello bob',
  senderPrivateKey: alicePrivateKey,
  recipientPublicKey: bobPublicKey,
);

final plaintext = Nip44.decryptMessage(
  payload,
  recipientPrivateKey: bobPrivateKey,
  senderPublicKey: alicePublicKey,
);
```

- Keys are hex strings. A public key is x-only (64 characters, as in Nostr events) or SEC1 encoded.
- The plaintext must be 1 to 4294967295 bytes in UTF-8: an empty string throws.
- `decrypt` and `decryptMessage` decode the whole payload in memory, with no size limit of their own: bound the size of a payload from an untrusted source before you decrypt it.
- The secp256k1 key agreement, which `Nip04` shares, does not run in constant time: its timing depends on the private key.

## Many messages with the same peer

`encryptMessage` and `decryptMessage` run the secp256k1 key agreement on every message.
To run it once per peer, compute the conversation key and pass it to `encrypt` and `decrypt`:

```dart
final conversationKey = Nip44.conversationKey(
  privateKey: alicePrivateKey,
  publicKey: bobPublicKey,
);

final payload = Nip44.encrypt('hello bob', conversationKey);
final reply = Nip44.decrypt(replyFromBob, conversationKey);
```

Both peers get the same conversation key.
The `nonce` of `encrypt` is for test vectors: a nonce must never be reused.

## Errors

- `Nip44InvalidMacException`: the payload was altered, or the keys do not match.
- `FormatException`: a key is not valid on secp256k1, or the payload is not a valid NIP-44 v2 payload (version, base64, size, padding or UTF-8). It never holds a key.
- `ArgumentError`: the plaintext is empty or longer than 4294967295 bytes, or a conversation key or a nonce is not 32 bytes.

## Through a signer

Most apps never call this package.
Every `NostrSigner` encrypts and decrypts for the account it holds, and `Bip340Signer` does it with `dostr_nip44`:

```dart
final ciphertext = await signer.encryptNip44(
  plaintext: 'hello bob',
  recipientPubkey: bobPublicKey,
);

final reply = await signer.decryptNip44(
  ciphertext: replyFromBob,
  senderPubkey: bobPublicKey,
);
```

Remote signers (NIP-46, NIP-07, NIP-55) encrypt where the key is, so the same code works with each of them.
The gift wrap of [`dostr_nip59`](https://pub.dev/packages/dostr_nip59) encrypts through the signer too.
The signer's `encryptNip04` and `decryptNip04` are the deprecated NIP-04 ones.

## NIP-04

`Nip04.encrypt` and `Nip04.decrypt` take the same arguments as `Nip44.encryptMessage` and `Nip44.decryptMessage`, with hex keys:

```dart
final payload = Nip04.encrypt(
  'hello bob',
  senderPrivateKey: alicePrivateKey,
  recipientPublicKey: bobPublicKey,
);
```

NIP-04 is AES-CBC with no MAC, so an altered payload is not always detected: use it only for peers that do not support NIP-44.
`decrypt` throws a `FormatException` when the payload is malformed or does not decrypt with these keys.

## Coming from `ndk`

`package:ndk/shared/nips/nip44/nip44.dart` and `package:ndk/shared/nips/nip04/nip04.dart` are now both in `package:dostr_nip44/dostr_nip44.dart`.

What changed:

| `ndk` | `dostr_nip44` |
|-------|---------------|
| `Nip44.deriveConversationKey(Nip44.computeSharedSecret(privateKey, publicKey))` | `Nip44.conversationKey(privateKey: privateKey, publicKey: publicKey)` |
| `await Nip44.encryptMessage(plaintext, privateKey, publicKey)` | `Nip44.encryptMessage(plaintext, senderPrivateKey: privateKey, recipientPublicKey: publicKey)`, synchronous |
| `await Nip44.decryptMessage(payload, privateKey, publicKey)` | `Nip44.decryptMessage(payload, recipientPrivateKey: privateKey, senderPublicKey: publicKey)`, synchronous |
| `Nip44.encryptMessage(plaintext, ..., customConversationKey: key, customNonce: nonce)` | `Nip44.encrypt(plaintext, key, nonce: nonce)` |
| `Nip44.decryptMessage(payload, ..., customConversationKey: key)` | `Nip44.decrypt(payload, key)` |
| `Nip04.encrypt(privateKey, publicKey, text)` | `Nip04.encrypt(text, senderPrivateKey: privateKey, recipientPublicKey: publicKey)` |
| `Nip04.decrypt(privateKey, publicKey, payload)` | `Nip04.decrypt(payload, recipientPrivateKey: privateKey, senderPublicKey: publicKey)` |
| a bare `Exception` | a `Nip44InvalidMacException`, a `FormatException` or an `ArgumentError`, see [Errors](#errors) |
| `Nip04.decrypt` returned an empty string for a payload without `?iv=` | throws a `FormatException` |
