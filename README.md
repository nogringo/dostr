# Dart Nostr Development Kit (NDK)

[![Build Status](https://github.com/relaystr/ndk/actions/workflows/tests.yaml/badge.svg?branch=master)](https://github.com/relaystr/ndk/actions?query=workflow%3A"tests"+branch%3Amaster)
[![Coverage](https://img.shields.io/codecov/c/github/relaystr/ndk?color=green)](https://codecov.io/github/relaystr/ndk)
[![Pub](https://img.shields.io/pub/v/ndk.svg)](https://pub.dev/packages/ndk)
[![License](https://img.shields.io/github/license/relaystr/ndk.svg)](LICENSE.txt)

NDK (Nostr Development Kit) is a Dart library that enhances the Nostr development experience.\
NDK supplies you with high-level usecases like lists or metadata while still allowing you to use low-level queries enhanced with inbox/outbox (gossip) by default.\
Our Target is to make it easy to build constrained Nostr clients, particularly for mobile devices.

# Get started here ➡️ [Documentation](https://dart-nostr.com/)

## [🔗 Contributing](https://dart-nostr.com/library-development/contributing/)

## Monorepo Packages

NDK ships as a small monorepo with focused packages for core, wallets, Flutter, and storage integrations.

### [🔗 Dart Nostr Development Kit (NDK)](./packages/ndk/#readme)

Core package of the NDK. Go here for instructions on how to use the NDK. 📜

### [🔗 NIP-01](./packages/nip01/)

`ndk_nip01`: the NIP-01 event (`Nip01Event`), its id computation, and the `EventVerifier` interface, in pure Dart.

### [🔗 Signer](./packages/signer/)

`ndk_signer`: the `EventSigner` interface that signers implement, with their pending requests and errors, in pure Dart.

### [🔗 Auth](./packages/auth/)

`ndk_auth`: the accounts NDK authenticates as, and the `AuthPolicy` and `AuthHandler` that decide when one is revealed to a relay (NIP-42) or a Blossom server.

### [🔗 Isolates](./packages/isolates/)

`ndk_isolates`: the isolate pool that NDK packages share for encoding and compute work, in pure Dart.

### [🔗 Logger](./packages/logger/)

`ndk_logger`: the logger that NDK packages share, with its levels and pluggable outputs, in pure Dart.

### [🔗 HTTP](./packages/http/)

`ndk_http`: the HTTP data source that NDK packages share, with typed errors for non-2xx responses and streamed uploads and downloads.

### [🔗 NIP-19](./packages/nip19/)

`ndk_nip19`: NIP-19 bech32 encoding and decoding (npub, nsec, note, nprofile, nevent, naddr), in pure Dart.

### [🔗 BIP-340](./packages/bip340/)

`ndk_bip340`: BIP-340 Schnorr signing and verification for Nostr events (event signer and verifier), in pure Dart.

### [🔗 NIP-44](./packages/nip44/)

`ndk_nip44`: NIP-44 encryption, and the deprecated NIP-04 encryption, in pure Dart.

### [🔗 NIP-49](./packages/nip49/)

`ndk_nip49`: NIP-49 private key encryption (`ncryptsec`) with a password.

### [🔗 NIP-77](./packages/nip77/)

`ndk_nip77`: NIP-77 negentropy sync on top of `ndk_core`, with the Negentropy V1 codec.

### [🔗 Rust verifier](./packages/rust_verifier/)

`ndk_rust_verifier`: fast BIP-340 event verifier in native Rust, through FFI. Needs the Rust toolchain.

### [🔗 Post-quantum](./packages/pq/)

`ndk_pq`: ML-DSA event signer and verifier, and post-quantum hybrid encryption, in native Rust through FFI. Experimental, needs the Rust toolchain.

### [🔗 URL sets](./packages/url_set/)

`ndk_url_set`: relay and Blossom server sets described rather than listed, stored offline and resolved later, in pure Dart.

### [🔗 Fetchers](./packages/fetchers/)

`ndk_fetchers`: an account's metadata, relay list, DM relays and Blossom servers, fetched from its write relays on top of `ndk_core`.

### [🔗 Wallets](./packages/wallets/)

`ndk_wallets`: one wallet API over Cashu, NWC, LNURL, BOLT12 and LNbits.

### [🔗 NWC](./packages/nwc/)

`ndk_nwc`: Nostr Wallet Connect (NIP-47) client and NWC zaps.

### [🔗 Cashu protocol](./packages/cashu_protocol/)

`ndk_cashu_protocol`: the Cashu protocol (blind signatures, v4 tokens, NUT-13 secrets and the mint API), without Nostr, in pure Dart.

### [🔗 Cashu](./packages/cashu/)

`ndk_cashu`: Cashu ecash wallet, on top of `ndk_cashu_protocol`.

### [🔗 Blossom](./packages/blossom/)

`ndk_blossom`: Blossom file storage, to upload, download, mirror and delete blobs on a user's servers, without depending on `ndk`.

### [🔗 NIP-17](./packages/nip17/)

`ndk_nip17`: NIP-17 private direct messages, with text and encrypted file messages, conversations and DM relay lists.

### [🔗 NIP-59](./packages/nip59/)

`ndk_nip59`: NIP-59 gift wrap, to create, seal, wrap and unwrap rumors, without depending on `ndk`. NDK exposes it as `ndk.giftWrap`.

### [🔗 NIP-85](./packages/nip85/)

`ndk_nip85`: NIP-85 trusted assertions, to fetch and stream the metrics trusted providers compute for users, events and addresses, without depending on `ndk`.

### [🔗 NIP-13](./packages/nip13/)

`ndk_nip13`: NIP-13 proof of work, to mine, measure and validate the difficulty of event ids off the main isolate, without depending on `ndk`.

### [🔗 NIP-07](./packages/nip07/)

`ndk_nip07`: NIP-07 signer, to sign and encrypt with the user's browser extension from any Dart web app, without depending on `ndk` or Flutter.

### [🔗 NIP-46](./packages/nip46/)

`ndk_nip46`: NIP-46 remote signing, to connect to a bunker with a `bunker://` or `nostrconnect://` URL and sign and encrypt through it, without depending on `ndk`. NDK exposes it as `ndk.bunkers`.

### [🔗 NIP-55](./packages/nip55/)

`ndk_nip55`: NIP-55 signer, to log in, sign and encrypt with a signer app on Android, as a Flutter plugin that does not depend on `ndk` or `ndk_flutter`.

### [🔗 ObjectBox](./packages/objectbox/)

ObjectBox database implementation.

### [🔗 Sembast](./packages/sembast/)

Sembast cache manager and wallets repository, in pure Dart.

### [🔗 Ndk Flutter](./packages/ndk_flutter/)

Flutter widgets and utilities that require Flutter as a dependency. It exports the NIP-07 signer of `ndk_nip07` and the NIP-55 signer of `ndk_nip55`.

### [🔗 CLI](./packages/cli/)

The `ndk` command line interface.

### [🔗 sample app](./packages/sample-app/)

example app using the NDK.
