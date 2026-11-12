---
label: Home
order: 101
icon: home
---

# Dart Nostr Development Kit (NDK)

[![Build Status](https://github.com/relaystr/ndk/actions/workflows/tests.yaml/badge.svg?branch=master)](https://github.com/relaystr/ndk/actions?query=workflow%3A"tests"+branch%3Amaster) [![Pub](https://img.shields.io/pub/v/ndk_core.svg)](https://pub.dev/packages/ndk_core) [![License](https://img.shields.io/github/license/relaystr/ndk.svg)](https://github.com/relaystr/ndk/blob/master/LICENSE)

NDK (Nostr Development Kit) is a set of Dart packages for building Nostr clients, particularly constrained ones such as mobile apps. Each package covers one part of Nostr and depends only on what it needs, so an app picks the parts it uses.

## Apps using NDK

[yana](https://github.com/frnandu/yana), [camelus](https://github.com/leo-lox/camelus), [zap.stream](https://github.com/nostrlabs-io/zap-stream-flutter), [zapstore](https://github.com/zapstore/zapstore), [freeflow](https://github.com/nostrlabs-io/freeflow), [hostr](https://github.com/sudonym-btc/hostr), [bitblik](https://github.com/bit-blik/bitblik), [donow](https://github.com/nogringo/donow), [submarine](https://github.com/nogringo/submarine), [nostr-mail-client](https://github.com/nogringo/nostr-mail-client)

# ➡️ [Getting Started 🔗](https://dart-nostr.com/guides/getting-started/)

# [Changelog 🔗](https://github.com/relaystr/ndk/blob/master/CHANGELOG.md)

---

## Features

### Relays (`ndk_core`)

- **REQ and EVENT on the relays you pick**, with verified events and an outcome per relay
- **Reconnects** with backoff, replaying the requests a connection carried
- **Idle connections closed** once nothing needs them
- **Relay limits** from NIP-11: REQs queued past `max_subscriptions`, messages past `max_message_length` not sent
- **NIP-42 authentication**, with the identity each request may reveal chosen per request

### Outbox model (`ndk_fetchers`, `ndk_url_set`, `ndk_home_relays`)

- **Account lists read where NIP-65 puts them**: relay lists, metadata, DM relays, Blossom servers
- **Batched lookups**, one REQ per relay for many pubkeys
- **Relay sets described rather than listed**, stored as JSON and resolved when the network is back
- **Any filter fetched from the relays a set resolves to**, each relay asked as soon as a list names it
- **Computed home relays**, to find the relay list of any pubkey

### Signers and accounts

- **Signers**: local BIP-340 (`ndk_bip340`), NIP-46 bunkers (`ndk_nip46`), NIP-07 browser extensions (`ndk_nip07`), NIP-55 Android signer apps (`ndk_nip55`)
- **Accounts** (`ndk_accounts`): log in, switch between accounts and sign as the current one
- **Pending requests** of external signers, to show and cancel them

### NIPs

- **Gift wrap** (NIP-59), **encryption** (NIP-44, NIP-04), **private key encryption** (NIP-49), **bech32 entities** (NIP-19)
- **Zaps** (NIP-57), **domain verification** (NIP-05), **proof of work** (NIP-13)
- **Negentropy sync** (NIP-77), **trusted assertions** (NIP-85)
- **Blossom** file storage

### Verification

- **Pure Dart** BIP-340 verification in an isolate (`ndk_bip340`)
- **Native Rust** verification through FFI (`ndk_rust_verifier`), much faster on mobile and desktop
- **Web** signing and verification with @noble/curves through JS interop (`ndk_web_crypto`), much faster in the browser

## Not included

- ready to use feeds, you build them from the packages (🚫 not planned)
