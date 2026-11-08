## 0.1.0

 - Initial release, moved out of the `ndk` package. It depends on neither `ndk` nor `ndk_core`. `ndk` depends on it and re-exports it.
 - `CachedRelayInfoRepo` wraps a `RelayInfoRepo` to fetch the info of a relay once and then serve it from memory, for `maxAge` if given. It is the cache `Connectivy` of `ndk` kept until now, which `ndk.connectivity.getRelayInfo` still goes through. It also remembers a relay without a document, and retries only a fetch that throws.
 - **BREAKING** `RelayInfoHttpRepoImpl.getRelayInfo` returns null only when the relay answers without a document. It throws when the relay could not be reached (a timeout, a network failure, a 408, a 429 or a 5xx), and throws an `ArgumentError` for a url that is not ws, wss, http or https. It reads at most `maxBytes`, 1 MiB by default.
 - `RelayInfo`, `RelayLimitation`, `RelayFees` and `RelayFee` have a `toJson` that `fromJson` reads back. Their lists are read-only.
