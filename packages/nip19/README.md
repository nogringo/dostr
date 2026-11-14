# dostr_nip19

[NIP-19](https://github.com/nostr-protocol/nips/blob/master/19.md) bech32
entities for Nostr: `npub`, `nsec`, `note`, `nprofile`, `nevent` and `naddr`.
Pure Dart, no relay or network code.

## Install

```yaml
dependencies:
  dostr_nip19: ^0.1.0
```

## Usage

Each entity is a class: `Npub`, `Nsec`, `Note`, `Nprofile`, `Nevent` and
`Naddr`. Build one from hex and `encode` it, or `decode` a string into one:

```dart
import 'package:dostr_nip19/dostr_nip19.dart';

final npub = Npub(
  '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
).encode();
final pubkey = Npub.decode(npub).pubkey;

final nevent = Nevent(
  eventId: 'b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696',
  relays: ['wss://relay.example.com'],
).encode();
print(Nevent.decode(nevent).relays);
```

`Nip19Entity.decode` takes any of them. `Nip19Entity` is sealed, so a `switch`
over it is exhaustive:

```dart
switch (Nip19Entity.decode(input)) {
  case Npub(:final pubkey) || Nprofile(:final pubkey):
    openProfile(pubkey);
  case Note(:final eventId) || Nevent(:final eventId):
    openEvent(eventId);
  case Naddr(:final kind, :final pubkey, :final identifier):
    openAddress(kind, pubkey, identifier);
  case Nsec():
    warnAboutSecret();
}
```

The decoders accept the `nostr:` prefix of
[NIP-21](https://github.com/nostr-protocol/nips/blob/master/21.md), except before
an `nsec`, which NIP-21 forbids. For the same reason, every class but `Nsec`
has a `uri` getter, its string with the `nostr:` prefix. Each class has a
`prefix` constant, such as `Npub.prefix`.

`Naddr.coordinate` is the `<kind>:<pubkey>:<identifier>` of an `a` tag.

`nevent` and `naddr` encode a `Nip01Event` of
[`dostr_nip01`](https://pub.dev/packages/dostr_nip01), with relay hints:

```dart
final nevent = event.nevent(relays: ['wss://relay.example.com']);
final naddr = event.naddr();
```

`nevent` holds the id, author and kind of the event. `naddr` holds its kind,
author and `d` tag, or an empty identifier for a replaceable event (kinds 0, 3
and 10000 to 19999). It returns null for any other kind, and for an
addressable event without a `d` tag.

Entities are values: two with the same fields are equal, and their `relays`
cannot be modified. `Nsec.toString` leaves the private key out.

## Errors

- `decode` throws a `FormatException` when the input is not valid bech32, has
  another prefix, misses a required field, or holds a key or id that is not 32
  bytes. No message quotes the input, since it may be an `nsec`.
- `tryDecode` returns null where `decode` throws.
- The constructors throw an `ArgumentError` when a key or id is not 32 bytes of
  hex, when a relay url or an `naddr` identifier is longer than 255 bytes, or
  when a kind does not fit 32 bits. They accept uppercase hex and keep it
  lowercase.

Unknown TLV entries are ignored, as NIP-19 asks, and so are relays that are not
valid UTF-8 and an `nevent` author or kind of the wrong length.

## Coming from `ndk`

`package:ndk/shared/nips/nip19/nip19.dart` is now
`package:dostr_nip19/dostr_nip19.dart`, and so are the `nevent` and `naddr`
methods on `Nip01Event`. The static `Nip19` class is gone:

| `ndk` | `dostr_nip19` |
| --- | --- |
| `Nip19.encodePubKey(pubkey)` | `Npub(pubkey).encode()` |
| `Nip19.encodePrivateKey(key)` | `Nsec(key).encode()` |
| `Nip19.encodeNoteId(id)` | `Note(id).encode()` |
| `Nip19.encodeNprofile(...)` | `Nprofile(...).encode()` |
| `Nip19.encodeNevent(...)` | `Nevent(...).encode()` |
| `Nip19.encodeNaddr(...)` | `Naddr(...).encode()` |
| `Nip19.decode(npub)` | `Npub.decode(npub).pubkey` |
| `Nip19.decode(nsec)` | `Nsec.decode(nsec).privateKey` |
| `Nip19.decode(note)` | `Note.decode(note).eventId` |
| `Nip19.decodeNprofile(s)` | `Nprofile.decode(s)` |
| `Nip19.decodeNevent(s)` | `Nevent.decode(s)` |
| `Nip19.decodeNaddr(s)` | `Naddr.decode(s)` |
| `Nip19.isPubkey(s)` | `Npub.tryDecode(s) != null` |
| `Nip19.isPrivateKey(s)` | `Nsec.tryDecode(s) != null` |
| `Nip19.isNoteId(s)` | `Note.tryDecode(s) != null` |
| `Hrps.kPublicKey` | `Npub.prefix` |
