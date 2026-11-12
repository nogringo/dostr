# Packages

There is no facade: each feature is its own package, built from the parts it needs.

| Need | Package | Main types |
|------|---------|------------|
| Relay connections, REQ, EVENT, NIP-42 | `ndk_core` | `RelayManager`, `RelayReqs`, `RelayPublishes` |
| Account lists (NIP-65, kind 0, 10050, 10063) | `ndk_fetchers` | `Nip65Fetcher`, `MetadataFetcher`, `DmRelaysFetcher`, `BlossomServersFetcher`, `EventFetcher` |
| Relay sets, resolved later | `ndk_url_set` | `UrlSet`, `resolveUrlSet`, `watchUrlSet` |
| Computed home relays | `ndk_home_relays` | `HomeRelayList` |
| Relay information (NIP-11) | `ndk_nip11` | `HttpRelayInfoRepo`, `CachedRelayInfoRepo` |
| Events and verification interface | `ndk_nip01` | `Nip01Event`, `Filter`, `EventVerifier` |
| Signing and verification | `ndk_bip340`, `ndk_rust_verifier`, `ndk_web_crypto` | `Bip340EventSigner`, `Bip340EventVerifier`, `RustEventVerifier`, `WebEventSigner`, `WebEventVerifier` |
| Accounts | `ndk_accounts` | `Accounts` |
| Remote signing (NIP-46) | `ndk_nip46` | `Bunkers`, `Nip46EventSigner` |
| Browser extension (NIP-07) | `ndk_nip07` | `Nip07EventSigner` |
| Android signer app (NIP-55) | `ndk_nip55` | `Nip55EventSigner` |
| bech32 (NIP-19) | `ndk_nip19` | |
| Encryption (NIP-44, NIP-04) | `ndk_nip44` | |
| Private key encryption (NIP-49) | `ndk_nip49` | |
| Gift wrap (NIP-59) | `ndk_nip59` | `GiftWrap` |
| NIP-05 | `ndk_nip05` | `Nip05Usecase` |
| Proof of work (NIP-13) | `ndk_nip13` | `Nip13` |
| Zaps (NIP-57) | `ndk_zaps` | `Zaps` |
| Negentropy (NIP-77) | `ndk_nip77` | `Nip77` |
| Trusted assertions (NIP-85) | `ndk_nip85` | |
| Blossom files | `ndk_blossom` | `Blossom`, `Files` |

Each package README has its standalone setup.
