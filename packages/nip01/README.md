# ndk_nip01

The [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) Nostr
event (`Nip01Event`), its id computation (`Nip01Utils`), and the
`EventVerifier` interface that signature verifiers implement.

Pure Dart, no relay or network code. A signature verifier such as
[`ndk_rust_verifier`](https://pub.dev/packages/ndk_rust_verifier) only needs
this package, not `ndk_core`.

[NDK](https://pub.dev/packages/ndk) and
[`ndk_core`](https://pub.dev/packages/ndk_core) depend on it and export it, so
apps that already use one of them don't need to add it.

## Install

```yaml
dependencies:
  ndk_nip01: ^0.1.0
```

## Usage

```dart
import 'package:ndk_nip01/ndk_nip01.dart';

final event = Nip01Event(
  pubKey: '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
  kind: Nip01Event.kTextNoteKind,
  tags: [
    ['t', 'nostr'],
  ],
  content: 'hello',
);

print(event.id);
print(Nip01Utils.isIdValid(event));
```

The constructor computes the id from the payload. `copyWith` gives a changed
payload its new id and drops a signature that no longer matches it.

To plug a verifier into NDK, implement `EventVerifier`:

```dart
class MyVerifier implements EventVerifier {
  @override
  Future<bool> verify(Nip01Event event) async {
    // check event.id against the payload, and event.sig against event.pubKey
  }
}
```

## Coming from `ndk_core`

`package:ndk_core/domain_layer/entities/nip_01_event.dart`,
`package:ndk_core/domain_layer/entities/nip_01_utils.dart` and
`package:ndk_core/domain_layer/repositories/event_verifier.dart` are now
`package:ndk_nip01/ndk_nip01.dart`. `package:ndk_core/ndk_core.dart` and
`package:ndk/ndk.dart` still export `Nip01Event`, `Nip01Utils` and
`EventVerifier`. `Nip01EventModel`, the JSON form of the event, stays in
`ndk_core`.
