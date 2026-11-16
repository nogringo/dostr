## 0.1.0

 - Initial release, moved out of `url_set_for_ndk` 0.2.1. Stored maps keep the same format.
 - `UrlListCheck` and `UrlListCheckStore` moved to `dostr_fetchers`, next to the lookups that keep them.
 - `UrlsUnavailable` names each unavailable list in `lists`, as an `UnavailableUrlList` with its pubkey, kind and reason, and keeps in `urls` what the set resolves to without them. `reason` joins the lists. `UrlSetSnapshot.unavailable` holds `UnavailableUrlList`s too.
 - `UrlSet.fromMap` throws a `FormatException` on a missing or mistyped field, where it threw a `TypeError`.
 - Two `UrlSet`s describing the same tree are equal.
 - `UrlSet.first` keeps the first URLs of a set.
 - `watchUrlSet` resolves a set as its lists arrive, with a `UrlListWatchFn` that streams each version of a list, and gives a `UrlSetSnapshot` on each change.
 - `cleanRelayUrl` and `cleanRelayUrls`, the relay url normalization, moved here from `ndk`, and `dostr_core` exports them too. The deep import `package:ndk/shared/helpers/relay_helper.dart` is now `package:dostr_url_set/dostr_url_set.dart`.
 - `cleanRelayUrl` accepts IPv6 addresses and a query without a path, which it rejected. It drops the fragment, which RFC 6455 forbids in WebSocket urls, where it kept it after a path and rejected the url otherwise. It also rejects a port above 65535.
