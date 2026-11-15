## 0.1.0

 - Initial release, moved out of the `ndk_flutter` package: `WebSigner`, `WebEventVerifier`, and `WebSignerFactory`, the web factory that `ndk_flutter` called `NdkEventSignerFactory`. `WebEventSigner` of `ndk_flutter` is now `WebSigner`, after the `NostrSigner` it implements.
 - `encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey`, as in `NostrSigner`, instead of `recipientPubKey` and `senderPubKey`.
