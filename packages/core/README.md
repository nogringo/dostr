# dostr_core

The core of Dostr: relay connections, NIP-42 authentication, and REQ and EVENT on the relays you pick, with nothing on top.
[`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers) builds on it to read the metadata and relay lists of accounts where NIP-65 puts them.

Use `dostr_core` on its own when you only talk to relays you already know, for a bot, a relay tool or a NIP-46 client.

## Install

```yaml
dependencies:
  dostr_core: ^0.1.0
  dostr_bip340: ^0.1.0
```

`dostr_core` has no signing or verification code of its own: it takes any `NostrSigner` and `EventVerifier`.
[`dostr_bip340`](https://pub.dev/packages/dostr_bip340) provides pure Dart ones.

## Usage

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';

final relays = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
);
final relay = RelayUrl.parse('wss://relay.example.com');

final reqs = RelayReqs(
  relayManager: relays,
  eventVerifier: Bip340EventVerifier(),
);
final req = reqs.req(
  relays: {
    relay: [
      Filter(kinds: [1], limit: 10),
    ],
  },
);
await for (final received in req.events) {
  print('${received.relayUrl}: ${received.event.content}');
}

final publishes = RelayPublishes(relayManager: relays);
final outcomes = await publishes
    .publish(signedEvent, relays: [relay])
    .done;
```

Keep one `RelayManager` for the whole app.
It holds the connections, and every `RelayReqs` and `RelayPublishes` built on it shares them.
Give it the limits of each relay from its NIP-11 document too, see [Relay limits](#relay-limits).
Without them, a connection keeps at most 20 REQs open.

A relay is named by a `RelayUrl`, the normalized url of [`dostr_relay_url`](https://pub.dev/packages/dostr_relay_url), which `dostr_core` exports.
Make one with `RelayUrl.parse`, which throws a `FormatException` when the url is not a relay's.
`RelayUrl.tryParse` returns null instead.
A `RelayUrl` is a `String`, so the urls that `dostr_core` gives back read as strings.

## Relay REQs

`RelayReqs` sends a NIP-01 REQ to the relays you pick: no cache, no outbox routing, no merging of identical requests, no pagination.
To ask the relays where an account publishes, see [`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers).

### Query

```dart
final req = reqs.req(
  relays: {
    relay: [
      Filter(kinds: [1], authors: [pubkey], limit: 20),
    ],
  },
  timeout: Duration(seconds: 10),
);

final events = await req.events.toList();
// per relay: eose, closed, notSent, disconnected, timedOut or cancelled
final outcomes = await req.done;
```

Without `timeout`, a query ends after `defaultQueryTimeout` (10 seconds).
A relay that never sends its EOSE cannot hold it open.

### Subscription

```dart
final sub = reqs.req(
  relays: {for (final url in relayUrls) url: [filter]},
  closeOnEose: false,
);

final listener = sub.events.listen(onEvent);

// sends the CLOSE, as sub.close() does
await listener.cancel();
```

A subscription has no timeout unless it is given one.
Once closed, it reports `eose` on the relays that caught up and `cancelled` on the others.
A relay where it still waited for a slot reports `notSent`, with `RelayFailureKind.connectionFull`, see [Relay limits](#relay-limits).

### What you get

- Each relay gets its filters in a single REQ. A filter that matches nothing is left out, and a relay left with no filter gets nothing.
- Events are signature-checked, and invalid ones are dropped.
- An event that matches none of the filters sent to its relay is dropped too. `search` is not checked, since each relay reads it its own way.
- Each event comes as a `RelayReqEvent`: the `event`, and the `relayUrl` that sent it.
- The events of a relay come in the order it sent them, even when the `EventVerifier` checks several at once. An event that is slow to check holds back the later events of its relay, never those of the others.
- Events are not deduplicated: an event that two relays hold arrives twice. `events.map((e) => e.event).distinctUnique()` from rxdart keeps each one once.
- `events` is a single-subscription stream. It keeps every event until it is listened to, without a limit, so listen to a subscription right away or close it.
- `auth` takes an `AuthPolicy`, see [NIP-42 authentication](#nip-42-authentication).

## Relay publishes

`RelayPublishes` sends a signed event to the relays you pick (NIP-01 EVENT): no signing, no cache, no outbox routing, no retry after a refusal.
To publish where the outbox model says, resolve the relays with a `UrlSet` of [`dostr_url_set`](https://pub.dev/packages/dostr_url_set) first.

```dart
final publishes = RelayPublishes(relayManager: relays);

final signed = await signer.sign(event);

final outcomes = await publishes
    .publish(
      signed,
      relays: ['wss://relay.example.com', 'wss://other.example.com'].map(RelayUrl.parse),
      timeout: Duration(seconds: 5),
    )
    .done;

outcomes.forEach((url, outcome) {
  print('$url: ${outcome.status.name} ${outcome.message}');
});
```

- Each relay gets the event once, even when the list names it twice.
- The `RelayPublishOutcome` of a relay is `pending` until it answers. It then becomes `accepted` or `refused`, with the `message` of its OK, `failed`, with the reason in `failure`, or `timedOut`.
- A relay that cannot be reached fails right away, with the reason in `failure`, rather than waiting for the timeout.
- When a connection goes away after its relay took the event but before its OK, the event goes out again once the connection is back. It fails with `RelayFailureKind.connectionLost` once nothing will bring that connection back, see [Reconnecting](#reconnecting).
- `done` completes once every relay answered, or after `timeout`, which leaves the others `timedOut`. `outcomes` and `outcomesStream` show the answers as they come, keyed by relay url as in `RelayReqs`. To move on once one relay accepted the event, wait on `outcomesStream`: the publish goes on for the others.
- `auth` takes an `AuthPolicy`. A relay that answers `auth-required` gets the event again, on a connection bound to the account that the policy allows, see [NIP-42 authentication](#nip-42-authentication).
- An unsigned event is refused with an `ArgumentError`.

## NIP-42 authentication

When a relay requires authentication, the `RelayManager` signs and sends the AUTH event, then retries the original request.

A connection carries at most one identity, chosen when it opens and fixed for its whole lifetime.
A request that authenticates therefore moves to a connection of its own.

### Which identity

Each REQ and EVENT says which identity it may be attributed to with an `AuthPolicy`, from `dostr_signer`:

- `AuthPolicy.never()` stays on the anonymous connection and never sends AUTH. A relay that refuses the request without an identity does not serve it.
- `AuthPolicy.allow(account)` starts anonymous and moves to a connection bound to `account` only once a relay refused the request without an identity.
- `AuthPolicy.require(account)` goes out on a connection bound to `account` from the start.

```dart
final req = reqs.req(
  relays: {RelayUrl.parse('wss://private.example.com'): [filter]},
  auth: AuthPolicy.allow(account),
);
```

`RelayReqs`, `RelayPublishes` and the negentropy sync of [`dostr_nip77`](https://pub.dev/packages/dostr_nip77) all take `auth`.

A request without `auth` authenticates only where the `AuthHandler` agrees.
It then uses the logged-in account of the `RelayManager`'s `accounts`, an `AuthAccounts` such as `Accounts` from [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).

### AuthHandler

Asked before a pubkey authenticates on a relay or a Blossom server.
Without one, a request that does not pass `auth` reveals no identity.

```dart
final relays = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
  accounts: accounts,
  authHandler: (url, pubkey) => askUser(url, pubkey),
);
```

- `never()` is never asked about. `allow(a)`, `require(a)` and a request without `auth` authenticate only where the handler returns true.
- `require` asks before sending, so a relay or server it refuses receives nothing. The others ask once a relay or server refused them.
- The handler is asked about a relay when a connection bound to that pubkey opens, and about a Blossom server once per operation.
- The time spent waiting on the handler does not count against the request timeout.

`authHandler: (_, _) async => true` authenticates as the logged-in account wherever asked.

## Connectivity

The `RelayManager` opens, keeps and closes the relay connections.

### Connection changes

```dart
// every connection, connected or not, each time one is added, starts
// connecting, opens, closes or is forgotten
relays.relayConnectivityChanges.listen((connections) {
  for (final c in connections) {
    print('${c.key.url}: ${c.isConnected}');
  }
});
```

A relay can have several connections: one anonymous, and one per identity it authenticated as.
Group them by `key.url` to show one status per relay.
Each list holds the connections as they stood when it was emitted, and nothing changes them afterwards.
Read `connectivities` for their state now.

### Reconnecting

A connection that drops is tried again at once.
Each later attempt waits 500 milliseconds, then twice as long as the one before, up to `reconnectMaximumDelay` (4 seconds by default).
A socket that drops again within 10 seconds of coming back waits for the next step, so a relay that drops every socket is not reconnected in a loop.

While the connection comes back:

- Its requests are replayed once it is back, and so are the REQs sent to it meanwhile.
- A query waits for it until its timeout.
- A publish sent to it waits for it as long as the publish lasts, and sends the event once it is back.
- An EVENT that the dropped socket took without an OK goes out again once it is back.

After `reconnectGiveUpAfter` (an hour by default), the connection is given up.
Null keeps trying for good.
A connection given up, closed or blocked ends its REQs as `disconnected`.
The relays its publishes still wait on fail with `RelayFailureKind.connectionLost`.
With `allowReconnect: false`, a connection is given up as soon as it drops.

A REQ does not try again a relay it could not reach less than `unreachableRelayRetryAfter` ago (a minute by default).
It ends there as `notSent`, with `RelayFailureKind.unreachable`.
`Duration.zero` tries every time.
A publish always tries again.

```dart
final relays = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
  reconnectGiveUpAfter: null,
  unreachableRelayRetryAfter: const Duration(seconds: 10),
);
```

### Blocked relays

`blockRelay(url)` closes the connections to a relay, and nothing connects to it again until `unblockRelay(url)`.
A REQ sent there meanwhile ends as `notSent` and a publish fails, both with `RelayFailureKind.blocked`.

When the app learns that the network is back, or comes back to the foreground, it does not have to wait for the backoff:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) relays.reconnectClosedConnections();
  if (state == AppLifecycleState.paused) relays.closeIdleConnections();
}
```

### Idle connections

A connection opens when a request or a publish goes to its relay.
It closes once it had nothing to do for `anonymousIdleTimeout` (a minute by default):

- no live subscription, and no request waiting for its answer,
- no publish or authentication in flight,
- no message sent or received.

A connection bound to an identity waits `authenticatedIdleTimeout` (five minutes by default), since opening it again means authenticating again.
Null keeps idle connections open.
`closeIdleConnections()` closes them right away.

```dart
final relays = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
  anonymousIdleTimeout: const Duration(seconds: 30),
  authenticatedIdleTimeout: null,
);
```

### Shutting down

`closeAllConnections()` closes every connection, as `closeConnection` does for one.
The manager connects again for the next request.
`dispose()` closes them for good: it ends every REQ and publish still in flight, and closes `relayConnectivityChanges`.
Opening a connection, a REQ or a publish on a disposed manager throws a `StateError`.

### Relay limits

`RelayManager` asks two callbacks each time a socket opens, and waits up to 2 seconds for them:

- `subscriptionLimit`: how many REQs the relay keeps open on one socket. The others wait for a slot. A REQ closed or timed out while it waits ends there as `notSent`, with `RelayFailureKind.connectionFull`. Subscriptions leave a quarter of the slots to queries, and at least one when there are several. Without an answer, the limit is 20, a tenth of what strfry accepts, so answer it from the NIP-11 document as below.
- `messageLengthLimit`: how many bytes the relay reads in one message. A longer message is not sent: a REQ ends there as `notSent`, and an EVENT fails, both with `RelayFailureKind.messageTooLong`.

Both are in the NIP-11 document of the relay, which [`dostr_nip11`](https://pub.dev/packages/dostr_nip11) fetches.
`CachedRelayInfoRepository` fetches it once per relay and refreshes it in the background.
`maxSubscriptions` and `maxMessageLength` read the limits from it, and give null for a relay that could not be reached:

```dart
import 'package:http/http.dart' as http;
import 'package:dostr_nip11/dostr_nip11.dart';

final relayInfo = CachedRelayInfoRepository(
  HttpRelayInfoRepository(http.Client()),
  maxAge: const Duration(hours: 1),
  failureMaxAge: const Duration(minutes: 1),
);

final relays = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
  subscriptionLimit: relayInfo.maxSubscriptions,
  messageLengthLimit: relayInfo.maxMessageLength,
);
```

Give `CachedRelayInfoRepository` a `RelayInfoCache` to keep the documents across restarts, so a socket does not wait for the network to read them.

A relay that publishes no limit may close a socket with a 1009 (message too big).
It reads less than the longest message written there, so nothing that long is sent to it again.
The other REQs go out again on the new socket.
`onMessageLengthLearned` gets the url and the most bytes the relay may still be sent.
Store them and answer `messageLengthLimit` from them after a restart, so the limit is not learned again with another 1009.

### WebSocket compression

Native applications can opt out of `permessage-deflate` negotiation:

```dart
final relays = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(
    compressionEnabled: false,
  ),
);
```

Disabling compression can reduce memory and codec overhead for long-running services, but sends more bytes for compressible traffic and can perform worse on bandwidth-constrained links.
Compression remains enabled by default.

Browser WebSocket APIs do not expose compression negotiation controls, so this setting has no effect on web builds.

## Protocols of your own

A protocol that runs over the relay connections besides REQs and EVENTs, such as the NIP-77 negentropy of [`dostr_nip77`](https://pub.dev/packages/dostr_nip77), imports `package:dostr_core/protocol.dart`.
Its `RelayProtocolHandler`, added with `addProtocolHandler`, receives the messages, CLOSED and NOTICE the `RelayManager` does not handle itself, and sends its own with `send`.

## Logging

`dostr_core` logs with [`logging`](https://pub.dev/packages/logging), under the name `dostr_core`, and prints nothing on its own.
To read its warnings and errors:

```dart
import 'package:logging/logging.dart';

Logger.root.onRecord.listen((record) {
  print('${record.level.name} ${record.loggerName}: ${record.message}');
});
```

`Logger.root.level = Level.FINE` adds the debug messages.

## Coming from `ndk`

What moved and what changed is in [Coming from `ndk`](https://github.com/nogringo/dostr/blob/master/doc/coming-from-ndk.md).
