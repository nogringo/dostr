---
name: ndk-core
description: NDK Dart packages for Nostr. ndk_core for relay connections, REQ and EVENT on chosen relays and NIP-42; ndk_fetchers and ndk_url_set for the outbox model; signers, accounts and one package per NIP.
metadata:
  author: relaystr
---

# NDK Skill

NDK is a set of Dart packages, not a binary: this is library development guidance. There is no `Ndk` facade: build the parts you need and wire them yourself.

## Quick Reference

| Topic | Reference |
|-------|-----------|
| Install, `RelayManager` and its options | [references/setup.md](references/setup.md) |
| REQ and EVENT on chosen relays, outbox reads and publishes | [references/requests.md](references/requests.md) |
| Signers and accounts | [references/accounts.md](references/accounts.md) |
| Which package for which NIP | [references/usecases.md](references/usecases.md) |

## One-Line Summary

```
RelayManager → RelayReqs / RelayPublishes → fetchers (ndk_fetchers) → UrlSet (ndk_url_set)
```
