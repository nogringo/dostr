# dostr_nip19

[NIP-19](https://github.com/nostr-protocol/nips/blob/master/19.md) bech32
encoding and decoding for Nostr: `npub`, `nsec`, `note`, `nprofile`, `nevent`
and `naddr`. Pure Dart, no relay or network code.

## Install

```yaml
dependencies:
  dostr_nip19: ^0.1.0
```

## Usage

```dart
import 'package:dostr_nip19/dostr_nip19.dart';

final npub = Nip19.encodePubKey(
  '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
);
final hex = Nip19.decode(npub);

final nevent = Nip19.encodeNevent(
  eventId: 'b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696',
  relays: ['wss://relay.example.com'],
);
final reference = Nip19.decodeNevent(nevent);
print(reference.eventId);
```

`nevent` and `naddr` encode a `Nip01Event` of
[`dostr_nip01`](https://pub.dev/packages/dostr_nip01), with relay hints. `nevent`
holds its id, author and kind, and `naddr` its `d` tag, author and kind. `naddr`
returns null unless the kind is addressable (or `0`, `3` or `41`) and the event
has a `d` tag:

```dart
final nevent = event.nevent(relays: ['wss://relay.example.com']);
final naddr = event.naddr();
```

Keys and ids are hex strings. `encodePubKey`, `encodePrivateKey` and
`encodeNoteId` give an `npub`, an `nsec` and a `note`. `encodeNprofile`,
`encodeNevent` and `encodeNaddr` add relay hints, and `decodeNprofile`,
`decodeNevent` and `decodeNaddr` read them back as `Nprofile`, `Nevent` and
`Naddr`.

## Errors

- `Nip19.decode` throws a `FormatException` when the input is not valid, or
  when an `npub`, `nsec` or `note` does not hold 32 bytes. For an `nprofile` or
  `nevent` it returns the pubkey or event id and drops the hints. Use
  `decodeNaddr` for an `naddr`.
- `decodeNprofile`, `decodeNevent` and `decodeNaddr` throw an `ArgumentError`
  for another prefix or a missing required field, and other exceptions when the
  string is not valid bech32.
- `encodeNprofile`, `encodeNevent` and `encodeNaddr` throw an `ArgumentError`
  when a pubkey or id is not 32 bytes, or when a relay url is longer than 255
  bytes.

`Nip19.isNip19` finds an entity in text, with or without the `nostr:` prefix of
[NIP-21](https://github.com/nostr-protocol/nips/blob/master/21.md). The decoders
do not accept that prefix: strip it first. `isPubkey`, `isPrivateKey` and
`isNoteId` tell whether a string is a whole, valid `npub`, `nsec` or `note`, so
a partial one, such as text still being typed, is not one.

## Coming from `ndk`

`package:ndk/shared/nips/nip19/nip19.dart` and the `Naddr`, `Nevent` and
`Nprofile` entities are now all in `package:dostr_nip19/dostr_nip19.dart`, and so
are the `nevent` and `naddr` methods on `Nip01Event`
(`package:ndk/shared/nips/nip19/nip19_event_references.dart`).
