## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `GiftWrap` takes its factory as `signerFactory` instead of `eventSignerFactory`. `wrapEvent` is no longer static: it uses that factory instead of taking one.
 - `toGiftWrap` takes `additionalTags`, which go on the wrap after its `p` tag, such as a NIP-40 `expiration`.
 - `sealRumor` and `toGiftWrap` leave the `sig` of a signed rumor out of its seal, so that the recipient never holds a signature it could show others.
 - `GiftWrap` throws a `GiftWrapException`: a `GiftWrapDecryptionException` when the signer cannot decrypt, an `InvalidGiftWrapException` when the wrap holds no valid seal and rumor, a `GiftWrapEncryptionException` when the signer cannot encrypt, and a `GiftWrapNoSignerException` when there is no signer. An event that is not a kind `1059` throws an `ArgumentError`. In `ndk`, they all threw a bare `Exception`, and a payload that was not JSON a `FormatException`.
 - `createRumor` returns the rumor instead of a `Future`.
 - `recipientPublicKey` of `wrapEvent` is now `recipientPubkey`, as in `toGiftWrap`, and `kGiftWrapEventkind` is now `kGiftWrapEventKind`.
