## 0.1.0

 - Initial release.
 - `UrlListCheck` and `UrlListCheckStore` moved here from `url_set_for_ndk`.
 - `UrlListCheck` has an optional `dTag`, so the checks of addressable lists of one kind no longer overwrite each other. `UrlListCheckStore.read` takes it as a named parameter: stores implemented on a database must key their checks by it too. A check without one stores the same map as before.
