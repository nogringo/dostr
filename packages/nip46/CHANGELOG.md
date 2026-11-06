## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it, re-exports it and still exposes `ndk.bunkers`. Keys come from the `LocalEventSignerFactory` only, so it no longer depends on `ndk_bip340`: `Bunkers.createNostrConnect` replaces `NostrConnect(relays:, clientMetadata:)`, and `NostrConnect` has `privateKey` and `publicKey` instead of a `KeyPair`.
