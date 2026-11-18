## 0.1.0

 - Initial release, moved out of the `ndk_flutter` package. It does not depend on Flutter, so pure Dart web apps can use it. It replaces the `nip07_event_signer` package.
 - `Nip07EventSigner` is now `Nip07Signer`, after the `NostrSigner` it implements.
 - `encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey`, as in `NostrSigner`, instead of `recipientPubKey` and `senderPubKey`.
 - As in `NostrSigner`, `encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, with named parameters, the four encryption methods return a `Future<String>` instead of a `Future<String?>`, `canSign` is a getter, `getPublicKey()` is the `publicKey` getter, and `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone.
 - **BREAKING** A `Nip07Signer` knows the user's pubkey from the start, so `publicKey` never throws: `Nip07Signer.connect()` completes once the extension sent it, and `Nip07Signer(publicKey: ...)` takes it, for an account restored from storage, instead of `cachedPublicKey`. `getPublicKeyAsync` is gone, and `Nip07Signer.isAvailable` tells whether the browser has an extension, as `Nip07Signer().canSign` did.
 - `Nip07Signer(publicKey: ...)` throws a `FormatException` for a pubkey that is not 64 lowercase hex characters, as `connect` already failed on one.
 - `connect` takes a `timeout`, 10 minutes by default, and throws a `SignerRequestFailedException` once it passes without a pubkey. It used to wait forever.
 - `Nip07Signer.waitForExtension()` waits for an extension that adds `window.nostr` after the page loads.
 - `Nip07Signer` and `connect` take an optional `verifier`, which checks the signature of every event the extension signs.
 - `sign` throws an `ArgumentError` for an event of another pubkey, and a `SignerRequestFailedException` when the extension returns an invalid event or signs as another account, such as after the user switched accounts in it. It used to return that event.
 - Without an extension, every request throws a `StateError` instead of an `Exception`, and an extension without NIP-04 or NIP-44 fails the request with a `SignerRequestFailedException` instead of a `SignerRequestRejectedException`.
 - A request the extension rejects throws a `SignerRequestRejectedException`, whether the user refused it or the extension failed, since NIP-07 does not tell the two apart. An answer the signer cannot use, such as a decrypted text that is not a string, throws a `SignerRequestFailedException`.
 - `dispose` fails the requests the extension has not answered yet with a `SignerRequestFailedException`, instead of leaving them waiting.
 - Request ids are unique across signers.
 - The pending requests are the `PendingSignRequest`, `PendingEncryptRequest` and `PendingDecryptRequest` of `dostr_signer`, so asking for the pubkey is no longer one.
