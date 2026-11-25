## 0.2.1

 - `CachedNostrSigner` wraps a signer and keeps what it decrypts with NIP-44 in a `DecryptionCache`, under an opaque key derived from the account pubkey, the sender pubkey and the ciphertext, so that each ciphertext asks the signer once. `decryptNip44FromCache` reads the cache alone, `clearCache` removes the plaintexts of the signer's pubkey, such as on logout, and `MemoryDecryptionCache` keeps the plaintexts until a restart.

## 0.2.0

 - `LocalSignerFactory.generateKeyPair` returns a `KeyPair`, a record with named `privateKey` and `publicKey` fields, so that one cannot be taken for the other.
 - `LocalSignerFactory.readOnly` throws a `FormatException` for a public key that is not the 64 lowercase hex characters NIP-01 requires.
 - `NostrSigner.sign` returns an event with the id of its payload, whatever id it was given.

## 0.1.0

 - Initial release, moved out of the `ndk` package, with the `ConcurrencyLimiterMixin` of interactive signers, and the accounts (`AuthAccounts`), `AuthPolicy` and `AuthHandler` that decide when one is revealed to a relay (NIP-42) or a Blossom server.
 - `EventSigner` of `ndk` is now `NostrSigner`, and `LocalEventSignerFactory` is now `LocalSignerFactory`, since a signer also encrypts and decrypts.
 - `recipientPubKey` of `encryptNip44` and `senderPubKey` of `decryptNip44` are now `recipientPubkey` and `senderPubkey`.
 - `NostrSigner` and `LocalSignerFactory` are interface classes, without the default implementations that no signer inherited. `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone: nothing read them.
 - `encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, and take the named parameters of `encryptNip44` and `decryptNip44`. The pubkey that `decrypt` called `destPubkey` was the sender's.
 - `encryptNip04`, `decryptNip04`, `encryptNip44` and `decryptNip44` return a `Future<String>` instead of a `Future<String?>`: a signer that cannot encrypt or decrypt throws.
 - `canSign` is a getter, and `getPublicKey()` is the `publicKey` getter.
 - `Account` and `AccountType` are gone: an account is its `NostrSigner`, which knows its pubkey and tells what it is with `canSign` and its class. `AuthPolicy.allow` and `AuthPolicy.require` take the signer, and `AuthPolicy.account` is now `signer`.
 - `AuthAccounts.getLoggedAccount()` returns the `NostrSigner` of the logged account, and `getAccount(pubkey)` replaces the `accounts` map, which exposed every account to look up one.
 - `AuthPolicy` no longer has `canonical`, `==` and `hashCode`: two policies for the same pubkey were equal even when one account could sign and the other could not. `toString` still names the kind and the pubkey.
 - `LocalSignerFactory.create` takes the private key alone and derives the public key, and `readOnly` makes a read-only signer from a public key. `create({privateKey, publicKey})` needed one of the two at run time, and kept a public key that did not match the private key. `derivePublicKey` is gone: `create(privateKey).publicKey` gives it.
 - `SignerRequestRejectedException` and `SignerRequestCancelledException` are both a `SignerRequestException`, a sealed class with the `requestId`, so a single `on SignerRequestException` catches both.
 - `SignerRequestFailedException`, a `SignerRequestException` too, is what a request throws when no valid result came back, such as a ciphertext that does not decrypt or an event signed by another pubkey. The queued requests that `ConcurrencyLimiterMixin.cancelAllQueued` drops throw it instead of a `StateError`.
 - `NostrSigner` says what its implementations do: an operation completes with its result or throws a `SignerRequestException`, `publicKey` never throws, and `sign` takes an event of that pubkey and returns one of that pubkey. Misusing a signer throws an `Error`: an `ArgumentError` for `sign` with an event of another pubkey, and any operation while `canSign` is false.
 - `PendingSignerRequest` is a sealed class: a `PendingSignRequest` has the `event`, a `PendingEncryptRequest` the `plaintext` and `recipientPubkey`, a `PendingDecryptRequest` the `ciphertext` and `senderPubkey`. `counterpartyPubkey` and `content` are gone.
 - `SignerMethod` and `PendingSignerRequest.method` are gone: the class of a request tells what it waits for, and the `scheme` of an encryption or a decryption, an `EncryptionScheme`, tells NIP-04 from NIP-44. Only signatures, encryptions and decryptions wait in `pendingRequests`, since the user does not approve `connect`, `getPublicKey`, `ping` or `switchRelays`, and the NIP-46 method names are in `dostr_nip46`.
 - `ConcurrencyLimiterMixin` throws a `RangeError` when `maxConcurrentRequests` is below 1, where it queued every request forever.
