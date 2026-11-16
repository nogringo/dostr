## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `Nip04` only exposes `encrypt` and `decrypt`, and takes the same keys as `Nip44`.
 - `Nip04.encrypt` and `Nip04.decrypt` take the text or payload first, then the private key and the public key, as `Nip44.encryptMessage` and `Nip44.decryptMessage` do.
 - `Nip04.decrypt` throws a `FormatException` instead of returning an empty string for a payload without `?iv=`, and on any other malformed payload.
 - `Nip44.conversationKey`, `Nip44.encrypt` and `Nip44.decrypt` replace `computeSharedSecret`, `deriveConversationKey` and the `customConversationKey` and `customNonce` parameters of `encryptMessage` and `decryptMessage`.
 - `Nip44` throws `Nip44InvalidMacException` when the MAC does not match, a `FormatException` for an invalid key or payload, and an `ArgumentError` for a plaintext that is empty or longer than 65535 bytes, instead of a bare `Exception`.
 - An invalid private key no longer ends up in the error message.
 - `Nip44.decryptMessage` rejects a payload whose padding is not the one NIP-44 requires.
