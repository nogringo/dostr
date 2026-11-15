## 0.1.0

 - Initial release, moved out of the `ndk_flutter` package. It does not depend on Flutter, so pure Dart web apps can use it. It replaces the `nip07_event_signer` package.
 - `Nip07EventSigner` is now `Nip07Signer`, after the `NostrSigner` it implements.
 - Outside the browser, `getPublicKey` returns the `cachedPublicKey` the signer was given, as in the browser, and throws an `UnsupportedError` only without one.
