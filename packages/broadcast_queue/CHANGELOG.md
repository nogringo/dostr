## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it, re-exports it and still retries `ndk.broadcast` through it. `PendingBroadcastDelivery` takes a `DeliveryStore`, which `CacheManager` implements, and callbacks to send and to resolve lists instead of `BroadcastSender`. It now answers `loadEventDelivery` and `loadDeliveries` itself.
