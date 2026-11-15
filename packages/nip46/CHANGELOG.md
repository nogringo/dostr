## 0.1.0

 - Initial release, moved out of the `ndk` package. Keys come from the `LocalSignerFactory` only, so it does not depend on `dostr_bip340`: `Bunkers.createNostrConnect` replaces `NostrConnect(relays:, clientMetadata:)`, and `NostrConnect` has `privateKey` and `publicKey` instead of a `KeyPair`.
 - `Nip46EventSigner` is now `Nip46Signer`, after the `NostrSigner` it implements. `Bunkers` and `Nip46Signer` take their factory as `signerFactory` instead of `eventSignerFactory`, and `localEventSigner` of `Nip46Signer` is now `localSigner`.
