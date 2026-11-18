## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `Nip04` only exposes `encrypt` and `decrypt`, and takes the same keys as `Nip44`.
 - `Nip04.encrypt`, `Nip04.decrypt`, `Nip44.encryptMessage` and `Nip44.decryptMessage` take the text or the payload first, then the keys as named parameters, so that a private key cannot take the place of a public key: `senderPrivateKey` and `recipientPublicKey` to encrypt, `recipientPrivateKey` and `senderPublicKey` to decrypt.
 - `Nip44.encryptMessage` and `Nip44.decryptMessage` return a `String` instead of a `Future<String>`: they always did the work on the calling isolate.
 - `Nip04.decrypt` throws a `FormatException` instead of returning an empty string for a payload without `?iv=`, and on any other malformed payload.
 - `Nip44.conversationKey`, `Nip44.encrypt` and `Nip44.decrypt` replace `computeSharedSecret`, `deriveConversationKey` and the `customConversationKey` and `customNonce` parameters of `encryptMessage` and `decryptMessage`. `conversationKey` takes `privateKey` and `publicKey` as named parameters.
 - `Nip44` throws `Nip44InvalidMacException` when the MAC does not match, a `FormatException` for an invalid key or payload, and an `ArgumentError` for a plaintext that is empty or longer than 4294967295 bytes, instead of a bare `Exception`.
 - No key ends up in an error message: neither an invalid private key nor an invalid public key, which could be a private key passed in its place.
 - `Nip44.decryptMessage` rejects a payload whose padding is not the one NIP-44 requires.
 - `Nip44.decrypt` and `Nip44.decryptMessage` reject a payload that is not standard base64 with padding, as NIP-44 requires, instead of decoding the URL-safe alphabet or a `%3D` padding.
 - `Nip44` encrypts and decrypts messages longer than 65535 bytes, up to 4294967295, with the 6-byte length prefix that NIP-44 added in nostr-protocol/nips#1907.
 - `Nip44.conversationKey` is 4 to 8 times faster: the secp256k1 key agreement runs on `dostr_secp256k1` instead of the pointycastle curve.
 - `Nip44.encrypt` and `Nip44.decrypt` are 2 to 4 times faster, with HMAC-SHA256 from `package:crypto`.
