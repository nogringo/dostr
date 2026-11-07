## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it, re-exports it and still exposes `UserRelayLists` as `ndk.userRelayLists` and `RelaySets` as `ndk.relaySets`.
 - `UserRelayLists` takes callbacks to query and publish instead of `Requests` and `Broadcast`, and any `AuthAccounts` of `ndk_auth` instead of `Accounts`.
 - `UserRelayLists.kRefreshUserRelayListDuration` replaces `REFRESH_USER_RELAY_DURATION` of `ndk`: how old the relay list of the logged account may be before an edit refreshes it.
 - A contact list read for its relays is cached as received. `ndk` cached a copy without its content, so without a query that caches what it receives, the relays it listed were lost.
