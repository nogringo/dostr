## 0.1.0

 - Initial release, moved out of `url_set_for_ndk` 0.2.1. Stored maps keep the same format.
 - `UrlListCheck` and `UrlListCheckStore` moved to `dostr_fetchers`, next to the lookups that keep them.
 - `UrlsUnavailable` names each unavailable list in `lists`, as an `UnavailableUrlList` with its pubkey, kind and reason, and keeps in `urls` what the set resolves to without them. `reason` joins the lists. `UrlSetSnapshot.unavailable` holds `UnavailableUrlList`s too.
 - `UrlSet.fromMap` throws a `FormatException` on a missing or mistyped field, where it threw a `TypeError`.
 - Two `UrlSet`s describing the same tree are equal, and `toString` writes a set as the constructors that build it.
 - `UrlListFound`, `UrlListNotFound`, `UrlListUnavailable`, `UrlsResolved`, `UrlsUnavailable` and `UrlSetSnapshot` are equal when they hold the same data, and `toString` shows it.
 - `UrlSet.first` keeps the first distinct URLs of a set, compared as written.
 - `watchUrlSet` resolves a set as its lists arrive, with a `UrlListWatchFn` that streams each version of a list, and gives a `UrlSetSnapshot` on each change.
