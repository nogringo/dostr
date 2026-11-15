## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `GiftWrap` and `GiftWrap.wrapEvent` take their factory as `signerFactory` instead of `eventSignerFactory`.
 - `sealRumor` and `toGiftWrap` leave the `sig` of a signed rumor out of its seal, so that the recipient never holds a signature it could show others.
