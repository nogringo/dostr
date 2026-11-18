## 0.1.0

 - Initial release, moved out of the `ndk_flutter` package: `WebSigner`, `WebEventVerifier`, and `WebSignerFactory`, the web factory that `ndk_flutter` called `NdkEventSignerFactory`. `WebEventSigner` of `ndk_flutter` is now `WebSigner`, after the `NostrSigner` it implements.
 - `encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey`, as in `NostrSigner`, instead of `recipientPubKey` and `senderPubKey`.
 - As in `NostrSigner`, `encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, with named parameters, the four encryption methods return a `Future<String>` instead of a `Future<String?>`, `canSign` is a getter, `getPublicKey()` is the `publicKey` getter, and `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone.
 - `encryptNip44` and `decryptNip44` handle messages longer than 65535 bytes, up to 4294967295, with the 6-byte length prefix that NIP-44 added in nostr-protocol/nips#1907.
 - `decryptNip44` rejects a payload whose padding is not the one NIP-44 requires, and checks the payload size as NIP-44 says.
 - `decryptNip04` and `decryptNip44` throw when the plaintext is not valid UTF-8, as `dostr_nip44` does, instead of replacing the invalid bytes with U+FFFD.
 - `WebSigner` keeps the NIP-44 conversation keys of its last 256 peers, so `encryptNip44` and `decryptNip44` run the key agreement once per peer instead of once per message.
 - **BREAKING** `privateKey` and `publicKey` of `WebSigner` are final.
 - As in `LocalSignerFactory`, `WebSignerFactory.create` takes the private key alone, `readOnly` takes a public key, `generateKeyPair` returns a `KeyPair`, and `derivePublicKey` is gone.
 - `WebSigner` throws a `FormatException` for a public key that is not 64 lowercase hex characters, and so does `WebSignerFactory.readOnly`, as `LocalSignerFactory` says.
 - As `NostrSigner` says, an encryption or a decryption that fails throws a `SignerRequestFailedException`, `sign` throws an `ArgumentError` for an event of another pubkey, and every operation of a read-only `WebSigner` throws a `StateError`.
