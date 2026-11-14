# dostr_core

The core of Dostr: relay connections, NIP-42 authentication, and REQ and
EVENT on the relays you pick, with nothing on top.
[`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers) builds on it to
read the metadata and relay lists of accounts where NIP-65 puts them.

Use `dostr_core` on its own when you only talk to relays you already know, for
a bot, a relay tool or a NIP-46 client.

## Install

```yaml
dependencies:
  dostr_core: ^0.11.0-dev.2
  dostr_bip340: ^0.1.0
```

`dostr_core` has no signing or verification code of its own: it takes any
`EventSigner` and `EventVerifier`. [`dostr_bip340`](https://pub.dev/packages/dostr_bip340)
provides pure Dart ones.

## Usage

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';

final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);

final reqs = RelayReqs(
  relayManager: relays,
  eventVerifier: Bip340EventVerifier(),
);
final req = reqs.req(
  relays: {
    'wss://relay.example.com': [
      Filter(kinds: [1], limit: 10),
    ],
  },
);
await for (final received in req.events) {
  print('${received.relayUrl}: ${received.event.content}');
}

final publishes = RelayPublishes(relayManager: relays);
final outcomes = await publishes
    .publish(signedEvent, relays: ['wss://relay.example.com'])
    .done;
```

Keep one `RelayManager` for the whole app: it holds the connections, which
every `RelayReqs` and `RelayPublishes` built on it shares.

## Relay REQs

`RelayReqs` sends a NIP-01 REQ to the relays you pick: no cache, no outbox
routing, no merging of identical requests, no pagination. To ask the relays
where an account publishes, see
[`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers).

### Query

```dart
final req = reqs.req(
  relays: {
    'wss://relay.example.com': [
      Filter(kinds: [1], authors: [pubkey], limit: 20),
    ],
  },
  timeout: Duration(seconds: 10),
);

final events = await req.events.toList();
// per relay: eose, closed, notSent, disconnected or timedOut
final outcomes = await req.done;
```

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

### Adding relays as you find them

Without `relays`, the request stays open until you `seal()` it, so a relay
that answers fast does not end it while you are still picking the others:

```dart
final req = reqs.req();
req.send('wss://a.example.com', [filterA]);
req.send('wss://b.example.com', [filterB]);
req.seal();
```

Each relay takes one `send`. Its filters travel in a single REQ, since a second
REQ with the same id replaces the first on the relay.

A relay can still be added after `seal()` while the request runs: it then has
to answer too before the request ends. `send` returns `false` and sends nothing
once the request is over, for a url that is not a relay's, and for a relay the
request was already sent to.

### What you get

- Events are signature-checked, and invalid ones are dropped.
- Each event comes as a `RelayReqEvent`: the `event`, and the `relayUrl` that
  sent it.
- Events are not deduplicated: an event two relays hold arrives twice, once
  from each. `events.map((e) => e.event).distinctUnique()` from rxdart keeps
  each one once.
- `events` is a single-subscription stream.
- `auth` takes an `AuthPolicy`, see
  [NIP-42 authentication](#nip-42-authentication).

## Relay publishes

`RelayPublishes` sends a signed event to the relays you pick (NIP-01 EVENT): no
signing, no cache, no outbox routing, no retry. To publish where the outbox
model says, resolve the relays with a `UrlSet` of
[`dostr_url_set`](https://pub.dev/packages/dostr_url_set) first.

```dart
final publishes = RelayPublishes(relayManager: relays);

final signed = await signer.sign(event);

final outcomes = await publishes
    .publish(
      signed,
      relays: ['wss://relay.example.com', 'wss://other.example.com'],
      timeout: Duration(seconds: 5),
    )
    .done;

for (final response in outcomes.values) {
  print('${response.relayUrl}: ${response.broadcastSuccessful} ${response.msg}');
}
```

- Each relay gets the event once, whatever the list holds twice.
- A relay that cannot be reached is reported as failed, with the reason in
  `msg` and `failure`, instead of waiting for the timeout.
- `done` completes once every relay answered, once `considerDonePercent` of
  them accepted the event, or after `timeout`. `outcomes` and `outcomesStream`
  show the answers as they come, keyed by relay url like those of `RelayReqs`.
- `auth` takes an `AuthPolicy`: a relay that answers `auth-required` gets the
  event again on a connection bound to the account it allows, see
  [NIP-42 authentication](#nip-42-authentication).
- An unsigned event is refused with an `ArgumentError`.

## NIP-42 authentication

When a relay requires authentication, the `RelayManager` signs and sends the
AUTH event, then retries the original request.

A connection carries at most one identity, chosen when it is opened and
immutable for its whole lifetime, so a request that authenticates moves to its
own connection.

### Which identity

Each REQ and EVENT says which identity it may be attributed to with an
`AuthPolicy`, from `dostr_signer`:

- `AuthPolicy.never()` stays on the anonymous connection and never sends AUTH.
  A relay that refuses the request without an identity does not serve it.
- `AuthPolicy.allow(account)` starts anonymous and moves to a connection bound
  to `account` only once a relay refused the request without an identity.
- `AuthPolicy.require(account)` goes out on a connection bound to `account`
  from the start.

```dart
final req = reqs.req(
  relays: {'wss://private.example.com': [filter]},
  auth: AuthPolicy.allow(account),
);
```

`RelayReqs`, `RelayPublishes` and the negentropy sync of
[`dostr_nip77`](https://pub.dev/packages/dostr_nip77) all take `auth`.

Without `auth`, a request authenticates as the account the `RelayManager` gets
from its `accounts`, an `AuthAccounts` such as `Accounts` from
[`dostr_accounts`](https://pub.dev/packages/dostr_accounts), and only where the
`AuthHandler` agrees.

### AuthHandler

Asked before a pubkey authenticates on a relay or a Blossom server. Without
one, a request that does not pass `auth` reveals no identity.

```dart
final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  accounts: accounts,
  authHandler: (url, pubkey) => askUser(url, pubkey),
);
```

- `never()` is never asked about. `allow(a)`, `require(a)` and a request
  without `auth` authenticate only where the handler returns true.
- `require` asks before sending, so a relay or server it refuses receives
  nothing. The rest asks once a relay or server refused.
- A relay is asked when a connection bound to that pubkey opens, a Blossom
  server once per operation.
- The time spent waiting on the handler does not count against the request
  timeout.

`authHandler: (_, _) async => true` authenticates as the logged-in account
wherever asked.

## Connectivity

The `RelayManager` opens, keeps and closes the relay connections.

### Connection changes

```dart
// every connection, connected or not, each time one changes
relays.relayConnectivityChanges.listen((connections) {
  for (final c in connections) {
    print('${c.url}: ${c.isConnected}');
  }
});
```

A relay can hold several connections, one anonymous and one per identity it
authenticated as, so group them by `url` to show one status per relay.

### Reconnecting

A connection that drops is retried right away, then after a wait that starts at
500 milliseconds and doubles, up to `reconnectMaximumStep` (4 seconds by
default), for an hour. Its requests are replayed once it is back. A socket that
drops again within 10 seconds of coming back is not retried right away, so a
relay that drops every socket is not reconnected in a loop.

When the app learns that the network is back, or comes back to the foreground,
it does not have to wait for the backoff:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) relays.reconnectClosedConnections();
  if (state == AppLifecycleState.paused) relays.closeIdleConnections();
}
```

### Idle connections

A connection opens when a request or a publish goes to its relay, and closes
once nothing needs it: no live subscription, no request waiting for its answer,
no publish or authentication in flight, and no message sent or received for
`anonymousIdleTimeout`, a minute by default. A connection bound to an identity
waits `authenticatedIdleTimeout`, five minutes by default, since opening it
again means authenticating again. Null keeps idle connections open.
`closeIdleConnections()` closes them right away.

```dart
final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  anonymousIdleTimeout: const Duration(seconds: 30),
  authenticatedIdleTimeout: null,
);
```

### Relay limits

`RelayManager` asks two callbacks each time a socket opens, and waits up to 2
seconds for them:

- `subscriptionLimit`: how many REQs the relay keeps open on one socket. The
  others wait for a slot, and subscriptions leave a quarter of them to queries.
  No answer gives 20.
- `messageLengthLimit`: how many bytes the relay reads in one message. A longer
  message is not sent: a REQ ends there as `notSent`, an EVENT fails, both with
  `RelayFailureKind.messageTooLong`.

Both are in the NIP-11 document of the relay, which
[`dostr_nip11`](https://pub.dev/packages/dostr_nip11) fetches.
`CachedRelayInfoRepo` fetches it once per relay and refreshes it in the
background:

```dart
import 'package:http/http.dart' as http;
import 'package:dostr_nip11/dostr_nip11.dart';

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

Give `CachedRelayInfoRepo` a `RelayInfoCache` to keep the documents across
restarts, so a socket does not wait for the network to read them.

A relay that publishes no limit and closes a socket with a 1009 reads less than
the longest message written there: nothing that long is sent to it again, and
the other REQs go out again on the new socket. `onMessageLengthLearned` gets
the url and the most bytes the relay may still be sent. Store them and answer
`messageLengthLimit` from them after a restart, so the limit is not learned
again with another 1009.

### WebSocket compression

Native applications can opt out of `permessage-deflate` negotiation:

```dart
final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(
    compressionEnabled: false,
  ),
);
```

Disabling compression can reduce memory and codec overhead for long-running
services, but sends more bytes for compressible traffic and can perform worse
on bandwidth-constrained links. Compression remains enabled by default.

Browser WebSocket APIs do not expose compression negotiation controls, so this
setting has no effect on web builds.

## Coming from `ndk`

What moved and what changed is in the
[changelog](https://pub.dev/packages/dostr_core/changelog).
