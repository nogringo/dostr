## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `Bip340EventSigner` is now `Bip340Signer`, and `Bip340EventSignerFactory` is now `Bip340SignerFactory`, after the `NostrSigner` they implement.
 - **BREAKING** `Bip340EventVerifier` verifies on the calling isolate: `useIsolate` is gone.
 - `Bip340EventVerifier` returns false, instead of throwing, on a malformed event, and rejects a sig or a pubkey that is not lowercase hex of the length NIP-01 sets. It used to accept a sig with extra characters after the first 128, and an uppercase pubkey.
