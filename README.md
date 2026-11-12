# Dart Nostr Development Kit (NDK)

[![Build Status](https://github.com/relaystr/ndk/actions/workflows/tests.yaml/badge.svg?branch=master)](https://github.com/relaystr/ndk/actions?query=workflow%3A"tests"+branch%3Amaster)
[![Coverage](https://img.shields.io/codecov/c/github/relaystr/ndk?color=green)](https://codecov.io/github/relaystr/ndk)
[![Pub](https://img.shields.io/pub/v/ndk_core.svg)](https://pub.dev/packages/ndk_core)
[![License](https://img.shields.io/github/license/relaystr/ndk.svg)](LICENSE)

NDK (Nostr Development Kit) is a set of Dart packages for building Nostr clients, particularly constrained ones such as mobile apps. Each package covers one part of Nostr and depends only on what it needs, so an app picks the parts it uses.

# Get started here ➡️ [Documentation](https://dart-nostr.com/)

## [🔗 Contributing](https://dart-nostr.com/library-development/contributing/)

## Monorepo Packages

### Relays and outbox

#### [🔗 Core](./packages/core/)

`ndk_core`: relay connections, NIP-42 authentication, and REQ and EVENT on the relays you pick. Start here.

#### [🔗 Fetchers](./packages/fetchers/)

`ndk_fetchers`: an account's metadata, relay list, DM relays and Blossom servers, fetched from its write relays on top of `ndk_core`, and any filter fetched from the relays a `UrlSet` resolves to.

#### [🔗 URL sets](./packages/url_set/)

`ndk_url_set`: relay and Blossom server sets described rather than listed, stored offline and resolved later, in pure Dart.

#### [🔗 Home relays](./packages/home_relays/)

`ndk_home_relays`: the home relays every client computes from a pubkey to find its NIP-65 relay list (Computed Home Relays NIP), in pure Dart.

#### [🔗 NIP-11](./packages/nip11/)

`ndk_nip11`: NIP-11 relay information, to fetch what a relay declares about itself, such as the limits `ndk_core` can apply, with an optional cache.

### Events, signers and accounts

#### [🔗 NIP-01](./packages/nip01/)

`ndk_nip01`: the NIP-01 event (`Nip01Event`), its id computation, and the `EventVerifier` interface, in pure Dart.

#### [🔗 Signer](./packages/signer/)

`ndk_signer`: the `EventSigner` interface that signers implement, with their pending requests and errors, and the accounts a request may authenticate as, with the `AuthPolicy` and `AuthHandler` that decide when one is revealed to a relay (NIP-42) or a Blossom server, in pure Dart.

#### [🔗 BIP-340](./packages/bip340/)

`ndk_bip340`: BIP-340 Schnorr signing and verification for Nostr events (event signer and verifier), in pure Dart.

#### [🔗 Rust verifier](./packages/rust_verifier/)

`ndk_rust_verifier`: fast BIP-340 event verifier in native Rust, through FFI. Needs the Rust toolchain.

#### [🔗 Accounts](./packages/accounts/)

`ndk_accounts`: log in with a private key, a public key, an external signer or a NIP-46 bunker, switch between the logged accounts and sign as the current one.

#### [🔗 NIP-46](./packages/nip46/)

`ndk_nip46`: NIP-46 remote signing, to connect to a bunker with a `bunker://` or `nostrconnect://` URL and sign and encrypt through it.

#### [🔗 NIP-07](./packages/nip07/)

`ndk_nip07`: NIP-07 signer, to sign and encrypt with the user's browser extension from any Dart web app, without Flutter.

#### [🔗 NIP-55](./packages/nip55/)

`ndk_nip55`: NIP-55 signer, to log in, sign and encrypt with a signer app on Android, as a Flutter plugin.

### NIPs

#### [🔗 NIP-19](./packages/nip19/)

`ndk_nip19`: NIP-19 bech32 encoding and decoding (npub, nsec, note, nprofile, nevent, naddr), in pure Dart.

#### [🔗 NIP-44](./packages/nip44/)

`ndk_nip44`: NIP-44 encryption, and the deprecated NIP-04 encryption, in pure Dart.

#### [🔗 NIP-49](./packages/nip49/)

`ndk_nip49`: NIP-49 private key encryption (`ncryptsec`) with a password.

#### [🔗 NIP-59](./packages/nip59/)

`ndk_nip59`: NIP-59 gift wrap, to create, seal, wrap and unwrap rumors.

#### [🔗 NIP-05](./packages/nip05/)

`ndk_nip05`: NIP-05 identifiers, to resolve a `name@domain` address to a pubkey and its relays and verify it, with caching.

#### [🔗 NIP-13](./packages/nip13/)

`ndk_nip13`: NIP-13 proof of work, to mine, measure and validate the difficulty of event ids off the main isolate.

#### [🔗 Zaps](./packages/zaps/)

`ndk_zaps`: NIP-57 zaps, to create zap requests, fetch the invoice to pay from a lightning address and read zap receipts.

#### [🔗 NIP-77](./packages/nip77/)

`ndk_nip77`: NIP-77 negentropy sync on top of `ndk_core`, with the Negentropy V1 codec.

#### [🔗 NIP-85](./packages/nip85/)

`ndk_nip85`: NIP-85 trusted assertions, to fetch and stream the metrics trusted providers compute for users, events and addresses.

#### [🔗 Blossom](./packages/blossom/)

`ndk_blossom`: Blossom file storage, to upload, download, mirror and delete blobs on a user's servers.

### Shared

#### [🔗 Isolates](./packages/isolates/)

`ndk_isolates`: the isolate pool that NDK packages share for encoding and compute work, in pure Dart.

#### [🔗 HTTP](./packages/http/)

`ndk_http`: the HTTP data source that NDK packages share, with typed errors for non-2xx responses and streamed uploads and downloads.

### Other

#### [🔗 Cashu protocol](./packages/cashu_protocol/)

`ndk_cashu_protocol`: the Cashu protocol (blind signatures, v4 tokens, NUT-13 secrets and the mint API), without Nostr, in pure Dart.

#### [🔗 Ndk Flutter](./packages/flutter/)

Flutter widgets and utilities that require Flutter as a dependency. It exports the NIP-07 signer of `ndk_nip07` and the NIP-55 signer of `ndk_nip55`.

#### [🔗 sample app](./packages/demo/)

example app using the NDK.
