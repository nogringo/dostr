# dostr_nip44

[NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md) encryption
for Nostr, in pure Dart, with the deprecated
[NIP-04](https://github.com/nostr-protocol/nips/blob/master/04.md) encryption
next to it for the clients and wallets that still need it.

[`dostr_bip340`](https://pub.dev/packages/dostr_bip340) depends on it:
`Bip340EventSigner` encrypts and decrypts with it. Add it on its own when you
encrypt with a private key you hold yourself.

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

- Keys are hex strings. A public key is x-only (64 characters, as in Nostr
  events) or SEC1 encoded.
- `encryptMessage` and `decryptMessage` return futures but do the work on the
  calling isolate, on every platform.
- The plaintext must be 1 to 65535 bytes: an empty string throws.
- Errors are untyped `Exception`s with a message. `Invalid MAC` means the
  payload was altered or the keys do not match. The others name a malformed
  payload or key.
- To skip the key agreement on each message to the same peer, compute the
  conversation key once with
  `Nip44.deriveConversationKey(Nip44.computeSharedSecret(privateKey, publicKey))`
  and pass it as `customConversationKey`. `customNonce` is for test vectors: a
  nonce must never be reused.

## Through a signer

Most apps never call this package. Every `EventSigner` encrypts and decrypts
for the account it holds, and `Bip340EventSigner` does it with `dostr_nip44`:

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

Remote signers (NIP-46, NIP-07, NIP-55) encrypt where the key is, so the same
code works with each of them. The gift wrap of
[`dostr_nip59`](https://pub.dev/packages/dostr_nip59) encrypts through the
signer too. The signer's `encrypt` and `decrypt` are the deprecated NIP-04 ones.

## NIP-04

`Nip04.encrypt(privateKey, publicKey, text)` and
`Nip04.decrypt(privateKey, publicKey, text)` are synchronous and take the text
last, unlike `Nip44`. The public key must be x-only. NIP-04 is AES-CBC with no
MAC, so an altered payload is not detected: use it only for peers that do not
support NIP-44. `decrypt` returns an empty string for a payload without `?iv=`.

## Coming from `ndk`

`package:ndk/shared/nips/nip44/nip44.dart` and
`package:ndk/shared/nips/nip04/nip04.dart` are now both in
`package:dostr_nip44/dostr_nip44.dart`.
