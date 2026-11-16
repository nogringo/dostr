## 0.1.1

 - `Filter.matches`, which tells whether an event meets every condition of a filter, its `search` aside, for a client to check what a relay sent.

## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `isLowercaseHex`, in `package:dostr_nip01/hex.dart`, for event verifiers to check that an id, a pubkey or a sig is the lowercase hex NIP-01 requires, with `bytesToHex` and `hexToBytes`, which convert between bytes and hex.
 - `EventKindClassification`, which tells regular, replaceable, addressable and ephemeral kinds apart, moved here from `ndk`, and `dostr_core` exports it too. The deep import `package:ndk/shared/nips/nip01/event_kind_classification.dart` is now `package:dostr_nip01/dostr_nip01.dart`. Unlike in `ndk`, kind 41 (NIP-28 channel metadata) is not replaceable, since NIP-01 makes kinds 4 to 44 regular, and `isParameterizedReplaceableKind`, `isRegularReplaceableKind` and `legacyReplaceableKinds` are gone: use `isAddressableKind` and `isReplaceableKind`.
 - `Filter`, the NIP-01 filter of a REQ, moved here from `ndk`, and `dostr_core` exports it too. The deep import `package:ndk/domain_layer/entities/filter.dart` is now `package:dostr_nip01/dostr_nip01.dart`. Unlike in `ndk`, `toMap` and `fromMap` are now `toJson` and `fromJson`, `fromJson` throws a `FormatException` for a malformed filter, where `tryFromJson` returns null, a tag name of any length is kept, and `tTags`, `mTags`, `cloneWithAuthors`, `cloneWithPTags` and `mergeAuthors` are gone.
 - `pubKey` of `Nip01Event`, in its constructor and `copyWith` too, is now `pubkey`, the name NIP-01 gives the field.
