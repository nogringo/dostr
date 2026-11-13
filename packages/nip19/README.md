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

## Coming from `ndk`

`package:ndk/shared/nips/nip19/nip19.dart` and the `Naddr`, `Nevent` and
`Nprofile` entities are now all in `package:dostr_nip19/dostr_nip19.dart`, and so
are the `nevent` and `naddr` methods on `Nip01Event`
(`package:ndk/shared/nips/nip19/nip19_event_references.dart`).
