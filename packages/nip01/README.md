# ndk_nip01

The [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) Nostr
event (`Nip01Event`), its JSON form, its id computation, and the
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
print(event.hasValidId);
```

The constructor computes the id from the payload. `copyWith` gives a changed
payload its new id and drops a signature that no longer matches it.
`withoutSig` gives an unsigned copy, and `payloadId` the id of the payload,
whatever id the event holds.

Two events with the same id are `==`, whatever their payload: check the id
before deduplicating events that are not verified yet.

`getTags` and `getFirstTag` read any tag. Only `p` and `d` have their own
getters, `pTags` and `dTag`, because NDK reads them everywhere: `p` names the
recipients of an event, `d` identifies an addressable event.

To read and write the JSON form:

```dart
final event = Nip01Event.tryFromJson(jsonDecode(json)); // null if malformed

event.toJson(); // the JSON object, a Map
event.toJsonString(); // the same as jsonEncode(event)
```

Both read only a well-formed event: string `pubkey` and `content`, int
`created_at` and `kind`, tags made of strings, and a string `id` and `sig`
when there are some. `fromJson` throws a `FormatException` where
`tryFromJson` returns null, like `int.parse` and `int.tryParse`. Prefer
`tryFromJson` for JSON from outside, such as a relay, a remote signer or a
seal. Both check the shape only, so that they read back whatever `toJson`
wrote.

Both keep the id they read, even a wrong one: check it with `hasValidId` or
an `EventVerifier` before trusting the event. When the JSON has no id, they
compute it. `toJson` leaves `sig` out of an unsigned event, such as a NIP-59
rumor.

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

`package:ndk_core/domain_layer/entities/nip_01_event.dart` and
`package:ndk_core/domain_layer/repositories/event_verifier.dart` are now
`package:ndk_nip01/ndk_nip01.dart`. `package:ndk_core/ndk_core.dart` and
`package:ndk/ndk.dart` still export `Nip01Event` and `EventVerifier`.

`Nip01EventModel` is now a deprecated alias of `Nip01Event`, in `ndk_core`.
`Nip01EventModel.fromEntity(event)` is gone: use `event` itself. `toBase64()`
is now an extension member, in
`package:ndk_core/data_layer/models/nip_01_event_model.dart`, which
`package:ndk_core/ndk_core.dart` and `package:ndk/ndk.dart` export.

`EventVerifier` is now an interface: implement it, `extends EventVerifier` no
longer compiles.

`Nip01Utils.calculateEventIdSync` is gone: a `Nip01Event` computes its own id,
and `event.payloadId` recomputes it from the payload. `toJson` no longer
writes `"sig": null` for an unsigned event.

`fromJson` is now strict. It used to read a missing `pubkey` or `content` as
`''`, missing `tags` as none, and to turn tag values into strings. It now
throws a `FormatException` for these. A missing `id`, which it read as `''`,
is now computed. `validSig` is gone: NDK only hands
out events it verified, and nothing read the flag.

The deprecated members are not in `ndk_nip01`. They stay in `ndk_core`, in
`package:ndk_core/domain_layer/entities/nip_01_utils.dart`, which
`package:ndk_core/ndk_core.dart` and `package:ndk/ndk.dart` export. The event
members are now extension members.

| Deprecated | Use |
| --- | --- |
| `Nip01EventModel` | `Nip01Event` |
| `Nip01Utils.isIdValid(event)` | `event.hasValidId` |
| `Nip01Utils.calculateId(event)` | `event.payloadId` |
| `event.getDtag()` | `event.dTag` |
| `event.getEId()` | `event.getFirstTag('e')` |
| `event.tTags` | `event.getTags('t')` |
| `event.replyETags` | the NIP-10 `reply` marker, read from `event.tags` |
