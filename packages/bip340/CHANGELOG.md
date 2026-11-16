## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `Bip340EventSigner` is now `Bip340Signer`, and `Bip340EventSignerFactory` is now `Bip340SignerFactory`, after the `NostrSigner` they implement.
 - `encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey`, as in `NostrSigner`, instead of `recipientPubKey` and `senderPubKey`.
 - `decrypt` throws a `FormatException` instead of returning an empty string for a NIP-04 payload without `?iv=`, and the NIP-44 methods throw the typed errors of `dostr_nip44`.
 - `Bip340Signer` keeps the NIP-44 conversation keys of its last 256 peers, so `encryptNip44` and `decryptNip44` run the key agreement once per peer instead of once per message.
 - **BREAKING** `privateKey` of `Bip340Signer` is final.
 - **BREAKING** `Bip340EventVerifier` verifies on the calling isolate: `useIsolate` is gone.
 - `Bip340EventVerifier` returns false, instead of throwing, on a malformed event, and rejects a sig or a pubkey that is not lowercase hex of the length NIP-01 sets. It used to accept a sig with extra characters after the first 128, and an uppercase pubkey.
