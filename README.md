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

### [🔗 Cashu](./packages/cashu/)

`ndk_cashu`: Cashu ecash wallet.

### [🔗 ObjectBox](./packages/objectbox/)

ObjectBox database implementation.

### [🔗 Sembast](./packages/sembast/)

Sembast cache manager and wallets repository, in pure Dart.

### [🔗 Ndk Flutter](./packages/ndk_flutter/)

Flutter widgets and utilities that require Flutter as a dependency, including the NIP-07 browser-extension signer.

### [🔗 CLI](./packages/cli/)

The `ndk` command line interface.

### [🔗 sample app](./packages/sample-app/)

example app using the NDK.
