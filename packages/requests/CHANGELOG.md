## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it, re-exports it and still exposes `Requests` as `ndk.requests`.
 - `Requests.kDefaultDesiredCoverage` is the coverage a request gets when it sets none, which `RequestDefaults.DEFAULT_BEST_RELAYS_MIN_COUNT` of `ndk` still forwards.
 - `RelaySetsEngine` requires its `bootstrapRelays`, like `JitEngine`. It fell back to the default bootstrap relays of `ndk` when they were null.
