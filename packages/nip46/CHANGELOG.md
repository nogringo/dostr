## 0.1.0

 - Initial release, moved out of the `ndk` package. Keys come from the `LocalEventSignerFactory` only, so it does not depend on `dostr_bip340`: `Bunkers.createNostrConnect` replaces `NostrConnect(relays:, clientMetadata:)`, and `NostrConnect` has `privateKey` and `publicKey` instead of a `KeyPair`.
