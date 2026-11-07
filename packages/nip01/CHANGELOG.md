## 0.1.0

 - Initial release, moved out of the `ndk_core` package.
 - `EventFilter`, the interface of the filters that drop events from a stream, moved here from `ndk_requests`, which still exports it.
 - `EventKindClassification`, which tells regular, replaceable, addressable and ephemeral kinds apart, moved here from `ndk_core`, which still exports it. The deep import `package:ndk_core/shared/nips/nip01/event_kind_classification.dart` is now `package:ndk_nip01/ndk_nip01.dart`.
 - `Filter`, the NIP-01 filter of a REQ, moved here from `ndk_core`, which still exports it. The deep import `package:ndk_core/domain_layer/entities/filter.dart` is now `package:ndk_nip01/ndk_nip01.dart`.
