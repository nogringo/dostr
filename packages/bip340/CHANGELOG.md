## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `Bip340EventSigner` is now `Bip340Signer`, and `Bip340EventSignerFactory` is now `Bip340SignerFactory`, after the `NostrSigner` they implement.
 - `encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey`, as in `NostrSigner`, instead of `recipientPubKey` and `senderPubKey`.
 - As in `NostrSigner`, `encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, with named parameters, the four encryption methods return a `Future<String>` instead of a `Future<String?>`, `canSign` is a getter, `getPublicKey()` is the `publicKey` getter, and `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone.
 - An encryption or a decryption that fails throws a `SignerRequestFailedException`, whose `cause` is the error of `dostr_nip44`, as `NostrSigner` says: `decryptNip04` used to return an empty string for a NIP-04 payload without `?iv=`.
 - `sign` throws an `ArgumentError` for an event of another pubkey, and every operation of a read-only `Bip340Signer` throws a `StateError`.
 - `Bip340Signer` keeps the NIP-44 conversation keys of its last 256 peers, so `encryptNip44` and `decryptNip44` run the key agreement once per peer instead of once per message.
 - **BREAKING** `privateKey` and `publicKey` of `Bip340Signer` are final.
 - As in `LocalSignerFactory`, `Bip340SignerFactory.create` takes the private key alone, `readOnly` takes a public key, and `derivePublicKey` is gone.
 - `Bip340` runs on the `Schnorr` signatures of `dostr_secp256k1` instead of the `bip340` package and the pointycastle curve: on native platforms, `verify` is about 12 times faster, and `sign`, `getPublicKey` and `generatePrivateKey` about 23 times.
 - `Bip340.sign` and `Bip340.verify` take a message of any length, as BIP-340 allows since 2022, instead of reading its first 32 bytes only, and `Bip340.sign` takes an optional `auxRand` for test vectors.
 - `Bip340.sign` and `Bip340.getPublicKey` throw a `FormatException` for a private key that is not 64 hex characters or not between 1 and n - 1, and `Bip340.verify` returns false instead of throwing on malformed input.
 - **BREAKING** `Bip340EventVerifier` verifies on the calling isolate: `useIsolate` is gone.
 - `Bip340EventVerifier` returns false, instead of throwing, on a malformed event, and rejects a sig or a pubkey that is not lowercase hex of the length NIP-01 sets. It used to accept a sig with extra characters after the first 128, and an uppercase pubkey.
