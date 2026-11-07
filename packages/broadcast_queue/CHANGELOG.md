## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it, re-exports it and still retries `ndk.broadcast` through it. `PendingBroadcastDelivery` takes a `DeliveryStore`, which `CacheManager` implements, and callbacks to send and to resolve lists instead of `BroadcastSender`. It now answers `loadEventDelivery` and `loadDeliveries` itself.
 - `startPeriodicRetry` takes an optional `openRelayUrlChanges` stream: a relay that opens gets its interactive signing retried and its targets flushed right away. `ndk` did this itself from `relayConnectivityChanges` until now, and `stop` now ends it.
 - `DeliverySend` completes with a `DeliveryResponse` for each relay instead of the `RelayBroadcastResponse` of `ndk_core`, and `DeliveryPolicy.resolveNextState` and `persistSpecificRelayBroadcastResult` take it too, so that this package does not depend on `ndk_core`. `toDeliveryResponse` of `ndk_broadcast` converts a `RelayBroadcastResponse`.
