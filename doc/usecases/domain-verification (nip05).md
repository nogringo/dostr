---
icon: verified
---

# Domain verification (NIP-05)

[`ndk_nip05`](https://pub.dev/packages/ndk_nip05) resolves a `name@domain` address to a pubkey and its relays through `/.well-known/nostr.json`, and checks that an address belongs to a pubkey ([NIP-05](https://github.com/nostr-protocol/nips/blob/master/05.md)).

```yaml
dependencies:
  ndk_nip05: ^0.1.0
  ndk_http: ^0.1.0
  http: ^1.6.0
```

## Example

:::code source="../../packages/nip05/example/ndk_nip05_example.dart" language="dart" range="5-35" title="" :::

To check an address against a pubkey you already have:

```dart
final result = await nip05.check(
  nip05: 'username@domain.example',
  pubkey: '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
);
print('valid? ${result.valid}, relays: ${result.relays}');
```

## Behavior

- `resolve` returns `Nip05Found`, `Nip05NotFound` or `Nip05ResolveError`, so a missing address is told apart from a server that could not be reached.
- `check` resolves the address and tells whether it points to the given pubkey.
- `cache` is a `Nip05Cache`, keyed by the canonical identifier (`Nip05.canonicalIdentifier`). Implement it on your storage to keep results across restarts.
- Concurrent calls for the same address share one request.
- `relays` lists the relays the domain gives for the pubkey, if any.

:::code source="../../packages/nip05/lib/src/config/nip_05_defaults.dart" language="dart" range="3-10" title="cache durations and timeout" :::
