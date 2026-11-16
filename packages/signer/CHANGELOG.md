## 0.1.0

 - Initial release, moved out of the `ndk` package, with the `ConcurrencyLimiterMixin` of interactive signers, and the accounts (`Account`, `AuthAccounts`), `AuthPolicy` and `AuthHandler` that decide when one is revealed to a relay (NIP-42) or a Blossom server.
 - `EventSigner` of `ndk` is now `NostrSigner`, and `LocalEventSignerFactory` is now `LocalSignerFactory`, since a signer also encrypts and decrypts.
 - `recipientPubKey` of `encryptNip44` and `senderPubKey` of `decryptNip44` are now `recipientPubkey` and `senderPubkey`.
 - `NostrSigner` and `LocalSignerFactory` are interface classes, without the default implementations that no signer inherited. `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone: nothing read them.
 - `encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, and take the named parameters of `encryptNip44` and `decryptNip44`. The pubkey that `decrypt` called `destPubkey` was the sender's.
 - `encryptNip04`, `decryptNip04`, `encryptNip44` and `decryptNip44` return a `Future<String>` instead of a `Future<String?>`: a signer that cannot encrypt or decrypt throws.
 - `canSign` is a getter.
 - `Account(signer)` takes only its signer and reads its pubkey from it, so its constructor no longer takes `pubkey` or `type`. `AccountType` is gone: the signer already tells what it is, with `canSign` and its class.
 - `AuthPolicy` no longer has `canonical`, `==` and `hashCode`: two policies for the same pubkey were equal even when one account could sign and the other could not. `toString` still names the kind and the pubkey.
 - `LocalSignerFactory.create` takes the private key alone and derives the public key, and `readOnly` makes a read-only signer from a public key. `create({privateKey, publicKey})` needed one of the two at run time, and kept a public key that did not match the private key. `derivePublicKey` is gone: `create(privateKey).getPublicKey()` gives it.
 - `SignerRequestRejectedException` and `SignerRequestCancelledException` are both a `SignerRequestException`, a sealed class with the `requestId`, so a single `on SignerRequestException` catches both.
 - `SignerMethod` no longer has `connect`, which no pending request ever had, nor `protocolString`: the NIP-46 method names are in `dostr_nip46`.
 - `ConcurrencyLimiterMixin` throws a `RangeError` when `maxConcurrentRequests` is below 1, where it queued every request forever.
