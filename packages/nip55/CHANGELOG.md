## 0.1.0

 - Initial release, moved out of the `ndk_flutter` package. It does not depend on `dostr_flutter`. The native side is now its own Android plugin, `Nip55Plugin`, on the `dostr_nip55` method channel.
 - `Nip55EventSigner` is now `Nip55Signer`, after the `NostrSigner` it implements. The `Nip55Signer` that talks to the signer app is now `Nip55SignerApp`, and `Nip55Signer` takes it as `signerApp` instead of `nip55Signer`.
 - `encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey`, as in `NostrSigner`, instead of `recipientPubKey` and `senderPubKey`. The `nip04Encrypt`, `nip04Decrypt`, `nip44Encrypt` and `nip44Decrypt` methods of `Nip55SignerApp` take `pubkey` instead of `pubKey`.
 - As in `NostrSigner`, `encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, with named parameters, the four encryption methods return a `Future<String>` instead of a `Future<String?>`, `canSign` is a getter, `getPublicKey()` is the `publicKey` getter, and `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone.
 - Given an npub, `Nip55Signer` keeps its pubkey in hex, so `publicKey` is the hex pubkey that it sends as `current_user`.
 - `sign` throws an `ArgumentError` for an event of another pubkey, and a `SignerRequestFailedException` when the signer app returns an invalid event or one signed by another account. It used to return that event, and to reject an invalid one with a `SignerRequestRejectedException`.
 - A queued request that `dispose` drops fails with a `SignerRequestFailedException` instead of a `SignerRequestRejectedException`, and the pending requests are the `PendingSignRequest`, `PendingEncryptRequest` and `PendingDecryptRequest` of `dostr_signer`.
