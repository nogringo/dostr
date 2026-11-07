## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it, re-exports it and still exposes `Requests` as `ndk.requests`.
 - `Requests.kDefaultDesiredCoverage` is the coverage a request gets when it sets none, which `RequestDefaults.DEFAULT_BEST_RELAYS_MIN_COUNT` of `ndk` still forwards.
 - `EventFilter` lives in `ndk_nip01`, so that filters can be written without depending on this package. This package still exports it.
 - `RelaySetsEngine` requires its `bootstrapRelays`, like `JitEngine`. It fell back to the default bootstrap relays of `ndk` when they were null.
 - `FilterFingerprint`, the hash that keys the fetched ranges of a filter, lives here next to `FetchedRanges` instead of `ndk_cache`, so that `ndk_cache` does not depend on `crypto` or `ndk_isolates`. `ndk` still exports it.
