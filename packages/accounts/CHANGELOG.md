## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `eventSignerFactory` is now `signerFactory`.
 - `loginPrivateKey` takes only the private key and derives the pubkey. In `ndk`, a pubkey that did not match the key made every signature invalid, without an error.
 - `addAccount` takes only its signer, without the `pubkey` and the `type` of `ndk`, and reads the pubkey from it. It returns the `Account`, and throws an `AccountExistsException` for a pubkey that is already an account, as the `login` methods do. In `ndk`, it replaced that account, the logged one included.
 - Each account owns its signer: `logout`, `removeAccount` and `dispose` dispose of it, so a NIP-46 bunker no longer keeps its relay subscription open. `logout` and `removeAccount` return a `Future` that completes once the signer is disposed of.
 - `authStateChanges` emits `null` on subscription when nobody is logged in, and no longer emits again when `switchAccount` picks the logged account.
 - `sign` throws an `AccountCannotSignException` when nobody logged in can sign, and an `ArgumentError` for an event of another pubkey. `switchAccount` throws an `UnknownAccountException`. In `ndk`, they all threw a bare `Exception`.
 - `getPublicKey()` is now the `loggedPubkey` getter, since it gives the pubkey of the logged account, or null, and not a signer's.
