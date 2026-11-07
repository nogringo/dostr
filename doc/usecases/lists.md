---
icon: list-unordered
---

[!badge variant="primary" text="high level"]

## Example

```dart
final myset = await ndk.lists.getSetByName(
  name: "myset",
  kind: Nip51List.kRelaySet,
);

if (myset == null) {
  print("set not found");
  return;
}
print("received a set with ${myset.elements.length} elements");
```

## How to use

We distinguish between **lists** and **sets**:
- **Lists**: Single lists identified by kind (e.g., bookmarks, mute list)
- **Sets**: Named collections identified by kind + name/d-tag (e.g., relay sets, follow sets)

Both can have public and private (encrypted) elements.

`Lists`, `Nip51List` and `Nip51Set` live in the `ndk_lists` package, which `ndk` depends on and re-exports. It does not depend on `ndk`: build `Lists` with `query`, `publish`, `cache` and `accounts`, see its [README](https://pub.dev/packages/ndk_lists).

## Current behavior

For public list/set content:

- reads use the latest visible event for the relevant list or set
- cached results are reused on later reads

For private list/set content:

- the original event content stays encrypted
- decrypted private tags can be loaded through NDK's decrypted payload cache
- repeated reads can reuse cached plaintext instead of decrypting again

### Lists Methods

#### getSingleNip51List

Retrieves a NIP-51 list by kind.

:::code source="../../packages/lists/lib/src/lists.dart" language="dart" range="144-158" title="" :::

#### addElementToList

Adds an element to a list. Creates the list if it doesn't exist.

:::code source="../../packages/lists/lib/src/lists.dart" language="dart" range="226-245" title="" :::

#### removeElementFromList

Removes an element from a list.

:::code source="../../packages/lists/lib/src/lists.dart" language="dart" range="275-292" title="" :::

### Sets Methods

#### getSetByName

Gets a specific set by name (d-tag) and kind.

:::code source="../../packages/lists/lib/src/lists.dart" language="dart" range="383-399" title="" :::

#### getPublicSets

Returns a stream of all public sets for a given public key and kind.

:::code source="../../packages/lists/lib/src/lists.dart" language="dart" range="438-452" title="" :::

#### addElementToSet

Adds an element to a named set. Creates the set if it doesn't exist.

:::code source="../../packages/lists/lib/src/lists.dart" language="dart" range="469-489" title="" :::

#### removeElementFromSet

Removes an element from a named set.

:::code source="../../packages/lists/lib/src/lists.dart" language="dart" range="526-547" title="" :::

#### setCompleteSet

Overwrites or creates a complete set. **Warning:** This replaces the entire set.

:::code source="../../packages/lists/lib/src/lists.dart" language="dart" range="592-606" title="" :::

#### deleteSet

Deletes a set by name and broadcasts a deletion event.

:::code source="../../packages/lists/lib/src/lists.dart" language="dart" range="630-644" title="" :::

## Common Use Cases

### Relay Sets
```dart
// Add relay to a set
await ndk.lists.addElementToSet(
  name: "my-relays",
  tag: "relay",
  value: "wss://relay.example.com",
  kind: Nip51List.kRelaySet,
);

// Get a relay set
final relaySet = await ndk.lists.getSetByName(
  name: "my-relays",
  kind: Nip51List.kRelaySet,
);
```

### Bookmarks
```dart
// Add bookmark
await ndk.lists.addElementToList(
  kind: Nip51List.kBookmarks,
  tag: "e",
  value: eventId,
);

// Get bookmarks
final bookmarks = await ndk.lists.getSingleNip51List(Nip51List.kBookmarks);
```

### Follow Sets
```dart
// Add to follow set
await ndk.lists.addElementToSet(
  name: "close-friends",
  tag: "p",
  value: pubkey,
  kind: Nip51List.kFollowSet,
);

// Stream all public follow sets
ndk.lists.getPublicSets(
  kind: Nip51List.kFollowSet,
  publicKey: somePubkey,
).listen((sets) {
  print("Found ${sets?.length ?? 0} follow sets");
});
```
