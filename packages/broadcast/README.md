# ndk_broadcast

Broadcasts for [NDK](https://pub.dev/packages/ndk): sign an event as the logged account and publish it to the outbox relays of its author (NIP-65) and the inbox relays of the pubkeys it tags, then keep retrying the relays that did not ack it through [`ndk_broadcast_queue`](https://pub.dev/packages/ndk_broadcast_queue). It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports `Broadcast` and exposes it as `ndk.broadcast`:

```dart
import 'package:ndk/ndk.dart';

final ndk = Ndk.defaultConfig();
final response = ndk.broadcast.broadcast(nostrEvent: note);
for (final outcome in await response.broadcastDoneFuture) {
  print('${outcome.relayUrl}: ${outcome.broadcastSuccessful}');
}
```

## Standalone

```yaml
dependencies:
  ndk_broadcast: ^0.1.0
  ndk_broadcast_queue: ^0.1.0
  ndk_cache: ^0.1.0
  ndk_core: ^0.11.0-dev.2
  ndk_url_set: ^0.1.0
  ndk_accounts: ^0.1.0
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_broadcast/ndk_broadcast.dart';
import 'package:ndk_broadcast_queue/ndk_broadcast_queue.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';

final cache = MemCacheManager();
final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final accounts = Accounts(const Bip340EventSignerFactory());

final sender = BroadcastSender(
  cacheManager: cache,
  urlLists: urlLists,
  bootstrapRelays: const ['wss://relay.primal.net'],
  relayManager: relayManager,
  accounts: accounts,
  considerDonePercent: 1,
  timeout: const Duration(seconds: 10),
  saveToCache: true,
);
final pendingDelivery = PendingBroadcastDelivery(
  store: cache,
  accounts: accounts,
  urlLists: urlLists,
  isEventInFlight: sender.isEventInFlight,
  send: (event, relayUrl, auth) => sender
      .broadcast(nostrEvent: event, specificRelays: [relayUrl], auth: auth)
      .broadcastDoneFuture,
);
final broadcast = Broadcast(
  broadcastSender: sender,
  accounts: accounts,
  cacheManager: cache,
  pendingDelivery: pendingDelivery,
);

final response = broadcast.broadcast(nostrEvent: note);
```

`urlLists` is a `UrlListFn` of [`ndk_url_set`](https://pub.dev/packages/ndk_url_set) that looks up the relay lists of a pubkey, for example with the fetchers of [`ndk_fetchers`](https://pub.dev/packages/ndk_fetchers). `accounts` is any `AuthAccounts` from [`ndk_auth`](https://pub.dev/packages/ndk_auth), such as the `Accounts` of [`ndk_accounts`](https://pub.dev/packages/ndk_accounts).

`BroadcastSender` sends once: it signs the event, resolves where it goes and publishes it. `Broadcast` adds the queue: the relays of `specificRelays`, and the parts of the `UrlSet` whose lists were unavailable, are retried until they ack, unless `retryDelivery` is `false`. `broadcastReaction` and `broadcastDeletion` (NIP-09) build the event for you.

Without `specificRelays` or `urlSet`, an event goes where `broadcastUrlSet` says: the outbox of its author, or `bootstrapRelays` once the author is known to have none, and the first `kMaxInboxRelaysToBroadcast` inbox relays of each `p` tag, except on a contact list. A gift wrap only goes to the DM relays of its recipients.

More in [example/](example/) and the [broadcast docs](https://dart-nostr.com/usecases/broadcast/).

## Coming from `ndk`

`Broadcast`, `NdkBroadcastResponse` and `BroadcastAuthUnavailableException` keep their names, and `package:ndk/ndk.dart` still exports them. The deep imports under `package:ndk/` (`domain_layer/usecases/broadcast/`, `domain_layer/entities/broadcast_response.dart` and `shared/nips/nip25/reactions.dart`) are now `package:ndk_broadcast/ndk_broadcast.dart`. `Broadcast` and `BroadcastSender` take any `AuthAccounts` instead of `Accounts`. `BroadcastDefaults.MAX_INBOX_RELAYS_TO_BROADCAST` of `ndk` forwards `kMaxInboxRelaysToBroadcast`.
