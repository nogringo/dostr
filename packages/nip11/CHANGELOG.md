## 0.1.0

 - Initial release, moved out of the `ndk` package. It depends on neither `ndk` nor `ndk_core`. `ndk` depends on it and re-exports it.
 - `CachedRelayInfoRepo` wraps a `RelayInfoRepo` to fetch the info of a relay once and then serve it from memory. It is the cache `Connectivy` of `ndk` kept until now, which `ndk.connectivity.getRelayInfo` still goes through.
