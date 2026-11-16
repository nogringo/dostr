## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `Nip77.reconcile` takes its `relayUrl` as a `RelayUrl`, from `dostr_core`, and no longer throws an `ArgumentError` for a url that is not a relay's. `Nip77Response` and the exceptions give theirs as a `RelayUrl` too.
