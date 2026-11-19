# dostr_signer_test_suite

A shared test suite for implementations of the `NostrSigner` and `LocalSignerFactory` of [`dostr_signer`](https://pub.dev/packages/dostr_signer).
Every signer runs the same cases, so they all keep the contract that `NostrSigner` documents.

The signers of Dostr (`dostr_bip340`, `dostr_noble`, `dostr_nip46`, `dostr_nip07`, `dostr_nip55`) run it, and so can any other signer.

## Usage

Add `dostr_signer_test_suite` as a **dev dependency**, with [`dostr_bip340`](https://pub.dev/packages/dostr_bip340) for the peer and the verifier of the example below:

```yaml
dev_dependencies:
  dostr_bip340: ^0.1.0
  dostr_signer_test_suite: ^0.1.0
```

Then in your test file:

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';

void main() {
  runSignerTestSuite(
    name: 'MySigner',
    createSigner: () => MySigner(...),
    createPeer: const Bip340SignerFactory().createWithNewKeyPair,
    verifier: Bip340EventVerifier(),
    interactive: true,
  );
}
```

`createSigner` returns a signer that can sign, and `verifier` checks its signatures.
`createPeer` returns a signer with a fresh key on each call, that the signer encrypts for and decrypts from.
`createReadOnlySigner`, when given, returns a signer whose `canSign` is false.

An `interactive` signer waits for the user: each request is in `pendingRequests` as soon as the call returns, until it completes or `cancelRequest` drops it.
A local signer lists none.

A `LocalSignerFactory` runs `runLocalSignerFactoryTestSuite` instead, which also runs `runSignerTestSuite` against the signers it creates and its read-only ones.
Its `createPeer` defaults to signers of the factory: pass those of another implementation, such as `Bip340SignerFactory`, to check that both encrypt alike.

## What's tested

| Group | What it verifies |
|-------|-----------------|
| **Signer** | `publicKey` is 64 lowercase hex characters, `canSign` is true |
| **sign** | Signs events with empty content, quotes, unicode, control characters and kind 0, with its pubkey and a valid signature; throws an `ArgumentError` for an event of another pubkey, or of its own in uppercase, and lists nothing as pending |
| **NIP-44, NIP-04** | Encrypts for and decrypts from a peer, both ways, a short, a unicode and a long text; decrypts concurrent requests each to its plaintext; throws a `SignerRequestException` for a ciphertext that does not decrypt, and for a NIP-44 ciphertext of another sender |
| **pendingRequests** | Empty once a request completes; `cancelRequest` is false for an unknown request. A local signer lists nothing while a request runs. An interactive signer lists each signature, encryption and decryption with what it waits for, gives each its own id, emits it on `pendingRequestsStream` then an empty list, and `cancelRequest` fails the request it drops with a `SignerRequestCancelledException`, and is false once it completed |
| **read-only** | `canSign` is false, `publicKey` is 64 lowercase hex characters, and signing, encrypting and decrypting throw a `StateError` and list nothing as pending |
| **LocalSignerFactory** | `generateKeyPair` makes a new lowercase hex key pair each time, `create` derives the public key of the private key, `readOnly` keeps the public key and cannot sign, and throws a `FormatException` for a public key that is not lowercase hex of 64 characters, `createWithNewKeyPair` makes a new key each time |
