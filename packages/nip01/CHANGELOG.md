## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `Nip01Event.kContactListKind` (3) and `Nip01Event.kDmRelayListKind` (10050), so that a package can name these kinds without depending on a package for contact lists or NIP-51 lists.
 - `EventFilter`, the interface of the filters that drop events from a stream.
 - `isLowercaseHex`, in `package:dostr_nip01/hex.dart`, for event verifiers to check that an id, a pubkey or a sig is the lowercase hex NIP-01 requires.
 - `EventKindClassification`, which tells regular, replaceable, addressable and ephemeral kinds apart, moved here from `ndk`, and `dostr_core` exports it too. The deep import `package:ndk/shared/nips/nip01/event_kind_classification.dart` is now `package:dostr_nip01/dostr_nip01.dart`. Unlike in `ndk`, kind 41 (NIP-28 channel metadata) is not replaceable, since NIP-01 makes kinds 4 to 44 regular.
 - `Filter`, the NIP-01 filter of a REQ, moved here from `ndk`, and `dostr_core` exports it too. The deep import `package:ndk/domain_layer/entities/filter.dart` is now `package:dostr_nip01/dostr_nip01.dart`.
