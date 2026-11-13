# Packages

There is no facade: each feature is its own package, built from the parts it needs.

| Need | Package | Main types |
|------|---------|------------|
| Relay connections, REQ, EVENT, NIP-42 | `dostr_core` | `RelayManager`, `RelayReqs`, `RelayPublishes` |
| Account lists (NIP-65, kind 0, 10050, 10063) | `dostr_fetchers` | `Nip65Fetcher`, `MetadataFetcher`, `DmRelaysFetcher`, `BlossomServersFetcher`, `EventFetcher` |
| Relay sets, resolved later | `dostr_url_set` | `UrlSet`, `resolveUrlSet`, `watchUrlSet` |
| Computed home relays | `dostr_home_relays` | `HomeRelayList` |
| Relay information (NIP-11) | `dostr_nip11` | `HttpRelayInfoRepo`, `CachedRelayInfoRepo` |
| Events and verification interface | `dostr_nip01` | `Nip01Event`, `Filter`, `EventVerifier` |
| Signing and verification | `dostr_bip340`, `dostr_rust_verifier`, `dostr_web_crypto` | `Bip340EventSigner`, `Bip340EventVerifier`, `RustEventVerifier`, `WebEventSigner`, `WebEventVerifier` |
| Accounts | `dostr_accounts` | `Accounts` |
| Remote signing (NIP-46) | `dostr_nip46` | `Bunkers`, `Nip46EventSigner` |
| Browser extension (NIP-07) | `dostr_nip07` | `Nip07EventSigner` |
| Android signer app (NIP-55) | `dostr_nip55` | `Nip55EventSigner` |
| bech32 (NIP-19) | `dostr_nip19` | |
| Encryption (NIP-44, NIP-04) | `dostr_nip44` | |
| Private key encryption (NIP-49) | `dostr_nip49` | |
| Gift wrap (NIP-59) | `dostr_nip59` | `GiftWrap` |
| NIP-05 | `dostr_nip05` | `Nip05Usecase` |
| Proof of work (NIP-13) | `dostr_nip13` | `Nip13` |
| Zaps (NIP-57) | `dostr_zaps` | `Zaps` |
| Negentropy (NIP-77) | `dostr_nip77` | `Nip77` |
| Trusted assertions (NIP-85) | `dostr_nip85` | |
| Blossom files | `dostr_blossom` | `Blossom`, `Files` |

Each package README has its standalone setup.
