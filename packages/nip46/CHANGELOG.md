## 0.1.0

 - Initial release, moved out of the `ndk` package. Keys come from the `LocalSignerFactory` only, so it does not depend on `dostr_bip340`: `Bunkers.createNostrConnect` replaces `NostrConnect(relays:, clientMetadata:)`, and `NostrConnect` has `privateKey` and `publicKey` instead of a `KeyPair`.
 - `Nip46EventSigner` is now `Nip46Signer`, after the `NostrSigner` it implements. `Bunkers` and `Nip46Signer` take their factory as `signerFactory` instead of `eventSignerFactory`, and `localEventSigner` of `Nip46Signer` is now `localSigner`.
 - `encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey`, as in `NostrSigner`, instead of `recipientPubKey` and `senderPubKey`.
 - As in `NostrSigner`, `encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, with named parameters, the four encryption methods return a `Future<String>` instead of a `Future<String?>`, `canSign` is a getter, and `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone.
 - `BunkerRequest.method` is the NIP-46 method name, such as `sign_event`, instead of a `SignerMethod`. `remoteRequest` takes the `SignerMethod` and its `params` instead of a `BunkerRequest`.
 - The relays of `BunkerConnection`, `NostrConnect`, `Bunkers.createNostrConnect` and `Nip46Signer.switchRelays` are `RelayUrl`s, from `dostr_core`. The relays of a `bunker://` url and of `BunkerConnection.fromJson` are normalized, and a url that is not a relay's is dropped.
 - `Nip46Signer.switchRelays` keeps the current relays when the remote signer sends none that is a relay url.
