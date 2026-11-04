# ndk_nip19

[NIP-19](https://github.com/nostr-protocol/nips/blob/master/19.md) bech32
encoding and decoding for Nostr: `npub`, `nsec`, `note`, `nprofile`, `nevent`
and `naddr`. Pure Dart, no relay or network code.

[NDK](https://pub.dev/packages/ndk) depends on it and exports it, so apps that
already use `ndk` don't need to add it.

## Install

```yaml
dependencies:
  ndk_nip19: ^0.1.0
```

## Usage

```dart
import 'package:ndk_nip19/ndk_nip19.dart';

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

## Coming from `ndk`

`package:ndk/shared/nips/nip19/nip19.dart` and the `Naddr`, `Nevent` and
`Nprofile` entities are now all in `package:ndk_nip19/ndk_nip19.dart`.
`package:ndk/ndk.dart` still exports them, along with the `nevent` and `naddr`
getters on `Nip01Event`.
