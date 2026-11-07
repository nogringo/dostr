---
icon: tag
---

[!badge variant="primary" text="high level"]

## Example

:::code source="../../packages/ndk/example/metadata_test.dart" language="dart" range="23-28" :::

## How to use

Gives you the metadata for a given pubkey. \
Uses caching, so repeated calls are ok.

Use `broadcastMetadata()` to update or set metadata.

`Metadatas` and `Metadata` live in the `ndk_metadatas` package, which `ndk` depends on and re-exports. It does not depend on `ndk`: build `Metadatas` with `query`, `publish`, `cache` and `accounts`, see its [README](https://pub.dev/packages/ndk_metadatas).

## Current behavior

Metadata behaves as replaceable event state.

That means:

- reads return the latest visible metadata event for the pubkey
- expired or deleted metadata events are not returned
- repeated reads can return cached results
- `forceRefresh` bypasses cached reads and refreshes from relays

When you broadcast metadata:

- the new metadata event is cached
- app reads can observe that cached state before every relay acknowledges it
