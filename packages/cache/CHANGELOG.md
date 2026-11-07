## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it and re-exports it.
 - `DecryptedEventPayloads`, the read-through cache of decrypted plaintext, moved here from `ndk` too, with `DecryptedPayloadsGiftWrapCache` and `DecryptedPayloadsNip51ListCache`, which plug it into the `GiftWrap` of `ndk_nip59` and the `Lists` of `ndk_lists`.
 - `UserRelayList.loadLatest` loads the relay lists a cache holds for some pubkeys, as `UserRelayLists.getUserRelayListCacheLatest` of `ndk` did.
