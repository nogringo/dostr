## 0.1.0

 - Initial release, moved out of `url_set_for_ndk` 0.2.1 with `UrlListCheckStore`. Stored maps keep the same format.
 - `UrlListCheck` has an optional `dTag`, so the checks of addressable lists of one kind no longer overwrite each other. `UrlListCheckStore.read` takes it as a named parameter: stores implemented on a database must key their checks by it too. A check without one stores the same map as before.
 - `UrlSet.first` keeps the first URLs of a set.
 - `watchUrlSet` resolves a set as its lists arrive, with a `UrlListWatchFn` that streams each version of a list, and gives a `UrlSetSnapshot` on each change.
 - `cleanRelayUrl` and `cleanRelayUrls`, the relay url normalization, moved here from `ndk_core`, which still exports them. The deep import `package:ndk_core/shared/helpers/relay_helper.dart` is now `package:ndk_url_set/ndk_url_set.dart`.
