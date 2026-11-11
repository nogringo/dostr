## 0.1.0

 - Initial release, moved out of the `ndk` package. It no longer depends on `ndk`: it takes its types from `ndk_cache`, `ndk_core`, `ndk_broadcast_queue`, `ndk_follows`, `ndk_metadata`, `ndk_nip01`, `ndk_nip05` and `ndk_nip11`.
 - Keeps the NIP-11 documents of `RelayInfoCache` in a `relay_infos` store.
 - Keeps the learned message lengths of relays in a `learned_message_lengths` store.
