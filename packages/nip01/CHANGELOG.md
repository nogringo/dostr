## 0.1.0

 - Initial release, moved out of the `ndk_core` package.
 - `Nip01Event.kContactListKind` (3) and `Nip01Event.kDmRelayListKind` (10050), which `ContactList.kKind` of `ndk_follows` and `Nip51List.kDmRelays` of `ndk_lists` now point to, so that a package can name these kinds without depending on either.
 - `EventFilter`, the interface of the filters that drop events from a stream, moved here from `ndk_requests`, which still exports it.
 - `EventKindClassification`, which tells regular, replaceable, addressable and ephemeral kinds apart, moved here from `ndk_core`, which still exports it. The deep import `package:ndk_core/shared/nips/nip01/event_kind_classification.dart` is now `package:ndk_nip01/ndk_nip01.dart`.
 - `Filter`, the NIP-01 filter of a REQ, moved here from `ndk_core`, which still exports it. The deep import `package:ndk_core/domain_layer/entities/filter.dart` is now `package:ndk_nip01/ndk_nip01.dart`.
