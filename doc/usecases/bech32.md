---
icon: link
label: Bech32 entities (NIP-19)
---

# Bech32 entities (NIP-19)

[`dostr_nip19`](https://pub.dev/packages/dostr_nip19) encodes and decodes the [NIP-19](https://github.com/nostr-protocol/nips/blob/master/19.md) bech32 entities: `npub`, `nsec`, `note`, `nprofile`, `nevent` and `naddr`. It is pure Dart, with no relay or network code.

```yaml
dependencies:
  dostr_nip19: ^0.1.0
```

## Example

:::code source="../../packages/nip19/example/dostr_nip19_example.dart" language="dart" range="4-15" title="" :::

Keys and ids are hex strings. `encodePubKey`, `encodePrivateKey` and `encodeNoteId` give an `npub`, an `nsec` and a `note`. `encodeNprofile`, `encodeNevent` and `encodeNaddr` add relay hints, and `decodeNprofile`, `decodeNevent` and `decodeNaddr` read them back as `Nprofile`, `Nevent` and `Naddr`.

## From an event

The package adds `nevent` and `naddr` to `Nip01Event`:

```dart
final nevent = event.nevent(relays: ['wss://relay.example.com']);
final naddr = event.naddr();
```

`nevent` holds the event's id, author and kind. `naddr` holds its `d` tag, author and kind, and is null unless the kind is addressable (or `0`, `3` or `41`) and the event has a `d` tag.

## Errors

- `Nip19.decode` never throws: it returns an empty string when the input is not valid. For an `nprofile` or `nevent` it returns the pubkey or event id and drops the hints. Use `decodeNaddr` for an `naddr`.
- `decodeNprofile`, `decodeNevent` and `decodeNaddr` throw an `ArgumentError` for another prefix or a missing required field, and other exceptions when the string is not valid bech32.
- `encodeNprofile`, `encodeNevent` and `encodeNaddr` throw an `ArgumentError` when a pubkey or id is not 32 bytes, or when a relay url is longer than 255 bytes.

`Nip19.isNip19` finds an entity in text, with or without the `nostr:` prefix of [NIP-21](https://github.com/nostr-protocol/nips/blob/master/21.md). The decoders do not accept that prefix: strip it first. `isPubkey`, `isPrivateKey` and `isNoteId` only check the prefix of a string.
