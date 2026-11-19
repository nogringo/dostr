## 0.1.0

 - Initial release.
 - `UrlListCheck` and `UrlListCheckStore` moved here from `url_set_for_ndk`, renamed `LookupCheck` and `LookupCheckStore` since they cover any replaceable event, metadata included. `MemoryUrlListCheckStore` is `MemoryLookupCheckStore`.
 - `LookupCheck` has an optional `dTag`, so the checks of addressable lists of one kind no longer overwrite each other. `LookupCheckStore.read` takes `kind`, `pubkey` and `dTag` as named parameters, like `ReplaceableEventCache.load`: stores implemented on a database must key their checks by `dTag` too. A check without one stores the same map as before.
 - `Nip65Fetcher` and `OutboxFetcher` extend `ReplaceableFetcher`, which holds their settings and their `watch`, `fetch`, `lookup`, `fetchAll` and `lookupAll`. `Nip65Fetcher` also has a `kind`, a `dTag` and a `name`.
 - A relay that closes a REQ is first asked for one of its pubkeys alone, and the others are split into smaller REQs only once it answered. A REQ closed for another reason than its size no longer turns into a REQ per filter, then per pubkey.
 - `EventFetch` keeps each event once while no one listens to `events`, and a late listener first gets those that came before it.
 - The relays of the fetchers are `RelayUrl`s, from `dostr_relay_url`: `writeRelaysOf`, `readRelaysOf`, `allRelaysOf` and `dmRelaysOf` return them, the `relays` of each fetcher takes them, and `EventFetchResult.outcomes` is keyed by them.
 - `blossomServersOf` returns `BlossomServerUrl`s, from `dostr_blossom_url`, and leaves out the servers `BlossomServerUrl.tryParse` rejects, such as a url with user info or a query.
 - `defaultIndexerRelays` is a `final` list, no longer a `const` one, and a fetcher given null `relays` asks it.
