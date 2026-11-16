## 0.1.0

 - Initial release, moved out of the `ndk_flutter` package. It does not depend on Flutter, so pure Dart web apps can use it. It replaces the `nip07_event_signer` package.
 - `Nip07EventSigner` is now `Nip07Signer`, after the `NostrSigner` it implements.
 - `encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey`, as in `NostrSigner`, instead of `recipientPubKey` and `senderPubKey`.
 - As in `NostrSigner`, `encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, with named parameters, the four encryption methods return a `Future<String>` instead of a `Future<String?>`, `canSign` is a getter, and `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone.
 - Outside the browser, `getPublicKey` returns the `cachedPublicKey` the signer was given, as in the browser, and throws an `UnsupportedError` only without one.
