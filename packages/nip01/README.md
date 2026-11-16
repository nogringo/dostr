# dostr_nip01

The [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) Nostr event (`Nip01Event`), its JSON form, its id computation, the `Filter` of a REQ, and the `EventVerifier` interface that signature verifiers implement.

Pure Dart, no relay or network code.
A signature verifier such as [`dostr_rust_verifier`](https://pub.dev/packages/dostr_rust_verifier) only needs this package, not `dostr_core`.

[`dostr_core`](https://pub.dev/packages/dostr_core) depends on it and exports it, so apps that already use `dostr_core` don't need to add it.

## Install

```yaml
dependencies:
  dostr_nip01: ^0.1.0
```

## Usage

```dart
import 'package:dostr_nip01/dostr_nip01.dart';

final event = Nip01Event(
  pubkey: '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
  kind: Nip01Event.kTextNoteKind,
  tags: [
    ['t', 'nostr'],
  ],
  content: 'hello',
);

print(event.id);
print(event.hasValidId);
```

The constructor computes the id from the payload.
`copyWith` gives a changed payload its new id and drops a signature that no longer matches it.
`withoutSig` gives an unsigned copy, and `payloadId` the id of the payload, whatever id the event holds.

Two events with the same id are `==`, whatever their payload: check the id before deduplicating events that are not verified yet.

`getTags` and `getFirstTag` read any tag.
Only `p` and `d` have their own getters, `pTags` and `dTag`, because the Dostr packages read them everywhere: `p` names the recipients of an event, `d` identifies an addressable event.

`EventKindClassification` tells the kinds of NIP-01 apart: replaceable (10000 to 19999, and 0 and 3), addressable (30000 to 39999) and ephemeral (20000 to 29999).
`isReplaceableKind` is true for the addressable kinds too, since a newer event replaces an older one in both: check `isAddressableKind` first to tell them apart.

To read and write the JSON form:

```dart
final event = Nip01Event.tryFromJson(jsonDecode(json)); // null if malformed

event.toJson(); // the JSON object, a Map
event.toJsonString(); // the same as jsonEncode(event)
```

Both read only a well-formed event: string `pubkey` and `content`, int `created_at` and `kind`, tags made of strings, and a string `id` and `sig` when there are some.
`fromJson` throws a `FormatException` where `tryFromJson` returns null, like `int.parse` and `int.tryParse`.
Prefer `tryFromJson` for JSON from outside, such as a relay, a remote signer or a seal.
Both check the shape only, so that they read back whatever `toJson` wrote.

Both keep the id they read, even a wrong one: check it with `hasValidId` or an `EventVerifier` before trusting the event.
When the JSON has no id, they compute it.
`toJson` leaves `sig` out of an unsigned event, such as a NIP-59 rumor.

`Filter` reads its JSON form the same way: `Filter.fromJson` throws a `FormatException` where `Filter.tryFromJson` returns null.

To write a verifier, implement `EventVerifier`:

```dart
class MyVerifier implements EventVerifier {
  @override
  Future<bool> verify(Nip01Event event) async {
    // check event.id against the payload, and event.sig against event.pubkey
  }
}
```

`package:dostr_nip01/hex.dart` has the hex helpers a verifier needs: `isLowercaseHex` checks that an id, a pubkey or a sig is the lowercase hex NIP-01 requires, and `bytesToHex` and `hexToBytes` convert between bytes and hex.

## Coming from `ndk`

`Nip01Event` and `EventVerifier` used to be in `ndk`.
What changed, and the deprecated members that `dostr_core` keeps, are in the [`dostr_core` changelog](https://pub.dev/packages/dostr_core/changelog).
