## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it and re-exports it.
 - `UserRelayList.loadLatest` loads the relay lists a cache holds for some pubkeys, as `UserRelayLists.getUserRelayListCacheLatest` of `ndk` did.
