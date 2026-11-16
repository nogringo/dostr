## 0.1.0

 - Initial release.
 - `UrlListCheck` and `UrlListCheckStore` moved here from `url_set_for_ndk`.
 - `UrlListCheck` has an optional `dTag`, so the checks of addressable lists of one kind no longer overwrite each other. `UrlListCheckStore.read` takes it as a named parameter: stores implemented on a database must key their checks by it too. A check without one stores the same map as before.
 - The relays of the fetchers are `RelayUrl`s, from `dostr_relay_url`: `writeRelaysOf`, `readRelaysOf`, `allRelaysOf` and `dmRelaysOf` return them, the `relays` of each fetcher takes them, and `EventFetchResult.outcomes` is keyed by them.
 - `defaultIndexerRelays` is a `final` list, no longer a `const` one, and a fetcher given null `relays` asks it.
