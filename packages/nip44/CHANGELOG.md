## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `Nip04` only exposes `encrypt` and `decrypt`, and takes the same keys as `Nip44`.
 - `Nip04.encrypt` and `Nip04.decrypt` take the text or payload first, then the private key and the public key, as `Nip44.encryptMessage` and `Nip44.decryptMessage` do.
 - `Nip04.decrypt` throws a `FormatException` instead of returning an empty string for a payload without `?iv=`, and on any other malformed payload.
 - `Nip44.conversationKey`, `Nip44.encrypt` and `Nip44.decrypt` replace `computeSharedSecret`, `deriveConversationKey` and the `customConversationKey` and `customNonce` parameters of `encryptMessage` and `decryptMessage`.
 - `Nip44` throws `Nip44InvalidMacException` when the MAC does not match, a `FormatException` for an invalid key or payload, and an `ArgumentError` for a plaintext that is empty or longer than 4294967295 bytes, instead of a bare `Exception`.
 - An invalid private key no longer ends up in the error message.
 - `Nip44.decryptMessage` rejects a payload whose padding is not the one NIP-44 requires.
 - `Nip44` encrypts and decrypts messages longer than 65535 bytes, up to 4294967295, with the 6-byte length prefix that NIP-44 added in nostr-protocol/nips#1907.
 - `Nip44.conversationKey` is 4 to 8 times faster: the secp256k1 key agreement runs on `dostr_secp256k1` instead of the pointycastle curve.
 - `Nip44.encrypt` and `Nip44.decrypt` are 2 to 4 times faster, with HMAC-SHA256 from `package:crypto`.
