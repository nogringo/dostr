---
icon: rss
---

# Connectivity

The `RelayManager` of [`ndk_core`](https://pub.dev/packages/ndk_core) opens, keeps and closes the relay connections. These are the knobs and signals it gives an app.

## Connection changes

```dart
// every connection, connected or not, each time one changes
relays.relayConnectivityChanges.listen((connections) {
  for (final c in connections) {
    print('${c.url}: ${c.isConnected}');
  }
});
```

A relay can hold several connections, one anonymous and one per identity it authenticated as (see [NIP-42](/concepts/nip42-auth.md)), so group them by `url` to show one status per relay.

## Reconnecting

A connection that drops is retried right away, then after a wait that starts at 500 milliseconds and doubles, up to `reconnectMaximumStep` (4 seconds by default), for an hour. Its requests are replayed once it is back. A socket that drops again within 10 seconds of coming back is not retried right away, so a relay that drops every socket is not reconnected in a loop.

When the app learns that the network is back, or comes back to the foreground, it does not have to wait for the backoff:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) relays.reconnectClosedConnections();
  if (state == AppLifecycleState.paused) relays.closeIdleConnections();
}
```

## Idle connections

A connection opens when a request or a publish goes to its relay, and closes once nothing needs it: no live subscription, no request waiting for its answer, no publish or authentication in flight, and no message sent or received for `anonymousIdleTimeout`, a minute by default. A connection bound to an identity waits `authenticatedIdleTimeout`, five minutes by default, since opening it again means authenticating again. Null keeps idle connections open. `closeIdleConnections()` closes them right away.

```dart
final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  anonymousIdleTimeout: const Duration(seconds: 30),
  authenticatedIdleTimeout: null,
);
```

## Relay limits

`RelayManager` asks two callbacks each time a socket opens, and waits up to 2 seconds for them:

- `subscriptionLimit`: how many REQs the relay keeps open on one socket. The others wait for a slot, and subscriptions leave a quarter of them to queries. No answer gives 20.
- `messageLengthLimit`: how many bytes the relay reads in one message. A longer message is not sent: a REQ ends there as `notSent`, an EVENT fails, both with `RelayFailureKind.messageTooLong`.

Both are in the NIP-11 document of the relay, which [`ndk_nip11`](https://pub.dev/packages/ndk_nip11) fetches. `CachedRelayInfoRepo` fetches it once per relay and refreshes it in the background:

```dart
import 'package:http/http.dart' as http;
import 'package:ndk_nip11/ndk_nip11.dart';

final relayInfo = CachedRelayInfoRepo(
  HttpRelayInfoRepo(http.Client()),
  maxAge: const Duration(hours: 1),
  failureMaxAge: const Duration(minutes: 1),
);

final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  subscriptionLimit: (url) async =>
      (await relayInfo.getRelayInfo(url))?.limitation?.maxSubscriptions,
  messageLengthLimit: (url) async =>
      (await relayInfo.getRelayInfo(url))?.limitation?.maxMessageLength,
);
```

Give `CachedRelayInfoRepo` a `RelayInfoCache` to keep the documents across restarts, so a socket does not wait for the network to read them.

### Learned message lengths

A relay that publishes no limit and closes a socket with a 1009 reads less than the longest message written there: nothing that long is sent to it again, and the other REQs go out again on the new socket. `onMessageLengthLearned` gets the url and the most bytes the relay may still be sent. Store them and answer `messageLengthLimit` from them after a restart, so the limit is not learned again with another 1009.
