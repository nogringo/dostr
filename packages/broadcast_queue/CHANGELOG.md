## 0.1.0

 - Initial release, moved out of `broadcast_queue_shim_for_ndk` 0.8.2 onto `dostr_core`. Stored queues keep the same format.
 - `OfflineBroadcast` is `BroadcastQueue`, and `OfflineBroadcast.withNdk` is `BroadcastQueue.withDostr`, which publishes through a `RelayManager` and takes the `relayListFn` that `withNdk` built itself, such as `fetcherUrlListFn` of `dostr_fetchers`.
 - `BroadcastFn` takes the relays as `RelayUrl`s and the `pubkey` the event was queued under, and returns the `RelayPublishOutcome` of each relay. `perAttemptTimeout` is `publishTimeout` on `withDostr`.
 - `withDostr` takes `authPolicyOf`, the NIP-42 `AuthPolicy` of each publish.
 - `QueuedBroadcast` holds its relays as `RelayUrl`s, normalized by `RelayUrl.tryParse`, and drops urls that are not ws or wss urls.
 - `UrlSet` comes from `dostr_url_set`, which is no longer re-exported.
 - `broadcast` throws an `ArgumentError` on an unsigned event.
 - An event too long for a relay is refused for good.
 - An attempt made offline is retried after `initialBackoff` without growing the backoff, and one in which a relay answered counts as online.
 - Without `onlineSignal`, `withDostr` reads the network from the connections of the `RelayManager` and never pauses the periodic retries, since `dostr_core` closes idle connections.
 - `dispose` abandons an attempt still waiting on the relays, and waits for the scans of due entries before the database can be closed.
