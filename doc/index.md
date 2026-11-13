---
label: Home
order: 101
icon: home
description: Dart packages for building Nostr applications, one package per part of Nostr.
---

# Dostr

[![Build Status](https://github.com/nogringo/dostr/actions/workflows/tests.yaml/badge.svg?branch=master)](https://github.com/nogringo/dostr/actions?query=workflow%3A"tests"+branch%3Amaster) [![Pub](https://img.shields.io/pub/v/dostr_core.svg)](https://pub.dev/packages/dostr_core) [![License](https://img.shields.io/github/license/nogringo/dostr.svg)](https://github.com/nogringo/dostr/blob/master/LICENSE)

Dostr is a set of Dart packages for building Nostr applications. Each package covers one part of Nostr and depends only on what it needs, so an application can pick the parts it uses.

## Start here

➡️ [Getting started](/guides/getting-started.md)

[Changelog](https://github.com/nogringo/dostr/blob/master/CHANGELOG.md)

---

## Features

### Relays (`dostr_core`)

- **REQ and EVENT on the relays you pick**, with verified events and an outcome per relay
- **Reconnects** with backoff, replaying the requests a connection carried
- **Idle connections closed** once nothing needs them
- **Relay limits** from NIP-11: REQs queued past `max_subscriptions`, messages past `max_message_length` not sent
- **NIP-42 authentication**, with the identity each request may reveal chosen per request

### Outbox model (`dostr_fetchers`, `dostr_url_set`, `dostr_home_relays`)

- **Account lists read where NIP-65 puts them**: relay lists, metadata, DM relays, Blossom servers
- **Batched lookups**, one REQ per relay for many pubkeys
- **Relay sets described rather than listed**, stored as JSON and resolved when the network is back
- **Any filter fetched from the relays a set resolves to**, each relay asked as soon as a list names it
- **Computed home relays**, to find the relay list of any pubkey

### Signers and accounts

- **Signers**: local BIP-340 (`dostr_bip340`), NIP-46 bunkers (`dostr_nip46`), NIP-07 browser extensions (`dostr_nip07`), NIP-55 Android signer apps (`dostr_nip55`)
- **Accounts** (`dostr_accounts`): log in, switch between accounts and sign as the current one
- **Pending requests** of external signers, to show and cancel them

### Flutter (`dostr_flutter`)

- **Widgets** for login, profiles, account switching and pending signer requests, in 13 languages
- **Accounts kept across restarts** in secure storage

### NIPs

- [**Gift wrap**](/usecases/gift-wrap.md) (NIP-59), [**encryption**](/usecases/encryption.md) (NIP-44, NIP-04), [**private key encryption**](/usecases/private-key-encryption.md) (NIP-49), [**bech32 entities**](/usecases/bech32.md) (NIP-19)
- [**Zaps**](/usecases/zaps.md) (NIP-57), [**domain verification**](/usecases/domain-verification.md) (NIP-05), [**proof of work**](/usecases/proof-of-work.md) (NIP-13)
- **Negentropy sync** (NIP-77), **trusted assertions** (NIP-85)
- **Blossom** file storage

### Verification

- **Pure Dart** BIP-340 verification in an isolate (`dostr_bip340`)
- **Native Rust** verification through FFI (`dostr_rust_verifier`), much faster on mobile and desktop
- **Web** signing and verification with @noble/curves through JS interop (`dostr_web_crypto`), much faster in the browser

## Not included

- ready to use feeds, you build them from the packages (🚫 not planned)
