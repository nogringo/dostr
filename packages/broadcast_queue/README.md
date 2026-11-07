# ndk_broadcast_queue

Persisted broadcast queue for Nostr: it keeps an event on its way to every relay it is meant for, across offline periods, delayed remote signing and app restarts.

It stores one delivery record per event and one target per relay, retries the targets that are due with a backoff that depends on the event kind, asks a remote signer again for the events it has not signed yet, and resolves later the relay lists that were unavailable when the event went out. It sends through a callback, which [`ndk_core`](https://pub.dev/packages/ndk_core) can answer, and depends on neither `ndk_core` nor `ndk`.

## With NDK

`ndk` depends on this package and re-exports it. Every `ndk.broadcast` goes through it unless you pass `retryDelivery: false`:

```dart
import 'package:ndk/ndk.dart';

ndk.broadcast.broadcast(nostrEvent: event, specificRelays: ['wss://relay.example.com']);

final pending = await ndk.broadcast.loadPendingDeliveries();
```

`NdkConfig(pendingDeliveryRetriesEnabled: false)` stops the background retries, and `pendingDeliveryRetryInterval` sets how often they run. The state lives in the `CacheManager`: it survives a restart with a persistent one.

## Standalone

```yaml
dependencies:
  ndk_broadcast_queue: ^0.1.0
  ndk_core: ^0.11.0-dev.2
  ndk_url_set: ^0.1.0
```

```dart
import 'package:ndk_broadcast_queue/ndk_broadcast_queue.dart';
import 'package:ndk_core/ndk_core.dart';

final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final relayPublishes = RelayPublishes(relayManager: relayManager);

final queue = PendingBroadcastDelivery(
  store: store,
  accounts: accounts,
  urlLists: urlLists,
  isEventInFlight: relayManager.isBroadcasting,
  send: (event, relayUrl, auth) async {
    final publish = relayPublishes.publish(event, relays: [relayUrl], auth: auth);
    return [
      for (final response in (await publish.done).values)
        DeliveryResponse(
          relayUrl: response.relayUrl,
          accepted: response.okReceived && response.broadcastSuccessful,
          message: response.msg,
          failure: response.failure?.toString(),
          identityNotAllowed:
              response.failure?.kind == RelayFailureKind.identityNotAllowed,
        ),
    ];
  },
);

await queue.enqueueSpecificRelayBroadcast(
  event: signedEvent,
  relayUrls: ['wss://relay.example.com'],
  requiresInteractiveSigning: false,
);
queue.startPeriodicRetry(
  connectedRelayUrls: () => relayManager.connectedRelays.map((r) => r.url),
  reconnectRelay: (url) => relayManager.reconnectRelay(url, force: true),
);
```

`store` is a `DeliveryStore`: the delivery records and relay targets, and the events they carry. `accounts` is the `AuthAccounts` of [`ndk_signer`](https://pub.dev/packages/ndk_signer), where a retry finds the signer and the NIP-42 identity of an event again after a restart. `urlLists` looks up the lists of an `UrlSet` from [`ndk_url_set`](https://pub.dev/packages/ndk_url_set). `send` must only publish, and complete with a `DeliveryResponse` for each relay: it is how a retry goes out, so it must not enqueue the event again. `toDeliveryResponse` of [`ndk_broadcast`](https://pub.dev/packages/ndk_broadcast) converts a `RelayBroadcastResponse` of `ndk_core`.

After the first send of an enqueued event, hand its answers to `persistSpecificRelayBroadcastResult` so the relays that accepted it are not retried. Call `enqueueUnresolvedUrlSets` with the parts of its `UrlSet` that could not be resolved yet. `loadEventDelivery` and `loadDeliveries` return the persisted state of each event, joined with its relay targets.

## Retries

`DeliveryPolicy` picks the retry behavior from the event kind:

- ephemeral events are sent once and never retried
- deletions (NIP-09) retry fastest
- replaceable and addressable events only keep retrying the newest version the store shows
- every other event retries with a backoff up to 15 minutes

A relay answer that cannot change, such as `blocked:` or `invalid:`, stops retries to that relay. An `auth-required:` answer is retried every minute, or never when the broadcast may reveal no identity (`AuthPolicy.never()`).

## Coming from `ndk`

The classes keep their names, and `package:ndk/ndk.dart` still exports them. The deep imports changed package: `package:ndk/domain_layer/usecases/broadcast/pending_broadcast_delivery.dart`, `package:ndk/domain_layer/usecases/broadcast/delivery_policy.dart` and `package:ndk/domain_layer/entities/event_delivery_inspection.dart` are now `package:ndk_broadcast_queue/ndk_broadcast_queue.dart`. So are `EventDeliveryRecord`, `RelayDeliveryTarget`, `UnresolvedUrlSet` and their enums, which left `package:ndk/domain_layer/entities/event_cache_records.dart`. `PendingBroadcastDelivery` takes `store`, `urlLists`, `send` and `isEventInFlight` instead of `cacheManager` and `broadcastSender`. `send` completes with `DeliveryResponse`s, and `persistSpecificRelayBroadcastResult` and `DeliveryPolicy.resolveNextState` take them, instead of `RelayBroadcastResponse`s.
