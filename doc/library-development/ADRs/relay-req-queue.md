# Architecture Decision Record: REQ queue per connection

Title: dostr_core holds back a REQ while its connection is full

## Context and Problem Statement

Relays cap the subscriptions open on one websocket (NIP-11
`limitation.max_subscriptions`, 200 by default on strfry). dostr_core sends every REQ
as soon as its connection is open, whatever is already open there.

Past the cap, strfry answers `["NOTICE", "ERROR: too many concurrent REQs"]`, which
names no subscription, and never a CLOSED. A query refused there waits for its
timeout. A subscription refused after its EOSE got its stored events, then silently
gets no new ones.

`RelayConnection.stats.openRequestIds` already tracks what is open on a socket, but
nothing reads it before sending.

## Main Proposal

### Unit: the connection

The budget belongs to a `RelayConnectionKey`, not to a url: the anonymous and the
bound connections to one relay are separate sockets, each with its own limit.

### Slots

A REQ holds a slot on its connection:

- taken when the gate lets it through, synchronously, before the write awaits
  `transport.ready`, so two sends in the same tick cannot both take the last slot
- released when we write a CLOSE, the relay sends a CLOSED, the write fails, or the
  socket goes away

An EOSE releases nothing by itself. A query gets its CLOSE right after its EOSE
(`handleEose`), a subscription keeps its slot past its EOSE until it is closed.

A REQ resent with an id that already holds a slot on that connection replaces it on
the relay and takes no new slot.

`RelayConnection` gets `reservedRequestIds` for the slots taken but not written
yet, each with the write it waits for, so a late write of a previous socket does
not release a slot of the current one. Used slots are `openRequestIds` plus
`reservedRequestIds`, and `openRequestIds` keeps meaning "written".

### Share kept for queries

Subscriptions hold at most `limit - limit ~/ 4` slots (15 of 20), queries may take
any slot.

strfry caps the database query and the live subscription that follows its EOSE
separately, so a connection full of subscriptions there still answers queries. One
budget for both would hold back queries strfry would have served.

### Limit

`RelayManager` takes a provider:

```dart
typedef SubscriptionLimit = FutureOr<int?> Function(String url);

RelayManager({SubscriptionLimit? subscriptionLimit, ...})
```

- dostr_core calls it once per connection, alongside opening its socket, and keeps
  the answer on the `RelayConnection` for the life of that socket. A reconnection
  asks again.
- No provider, `null`, or no answer within `SUBSCRIPTION_LIMIT_TIMEOUT` gives
  `DEFAULT_MAX_SUBSCRIPTIONS_PER_CONNECTION` (20). Both live in
  `relay_defaults.dart`. The timeout, 2 seconds, counts from the call, so it runs
  alongside the socket opening.
- The gate writes no REQ on a connection before its limit is known: they wait in
  its queue, so the first burst already respects the limit.
- dostr_core does no HTTP, so `ndk` provides it and owns the precedence:
  `NdkConfig.subscriptionLimit`, of the same type, then the NIP-11
  `max_subscriptions` that `Connectivity.getRelayInfo` already caches. strfry
  publishes its limit there.
- `getRelayInfo` remembers a relay that answered without NIP-11 as it remembers a
  document, for an hour, so a connection to it does not fetch again and wait for the
  timeout. A relay that could not be reached is asked again after a minute, so a
  connection opened within that minute keeps the limit of its last document, or
  the default when it never answered.
- Past that hour, `getRelayInfo` serves the last answer at once and fetches the
  relay again in the background, so only a relay that never answered makes a
  connection wait for NIP-11.

### Gate and queue

Every REQ write goes through one gate in `RelayRequests`: the first send
(`_sendTrackedRequest`), the replay on a new socket (`replayOn`) and the auth retries
(`_sendRequest`). With a free slot it writes, otherwise it appends the request to the
queue of that connection.

- Draining runs when a slot is freed and when the limit becomes known.
- Draining takes, in order, the first request that fits: a subscription held back
  by its share does not hold back the queries queued after it.
- Slots are counted in `RelayConnections`, which already counts `openRequestIds`.
  It tells `RelayRequests` through a new `ConnectionListener.admitQueuedOn(connection)`.
- The queue is a `ReqQueue` owned by `RelayRequests`, which shares its in-flight
  requests with it so it knows whether a queued request still matters. Draining
  skips a request no longer in flight or already ended on that connection.
- A queued request is tracked in `RequestState.requests` like a sent one, on an
  open connection, so `_checkNetworkClose` keeps waiting for it. It forgets what
  the relay answered before as soon as it is queued (`forgetAnswers`): a CLOSED
  auth-required it still carried would make it look ended, and get it dropped
  from its queue or given up by `endAuthRetriesOn`.
- `close()` drops the request from the queues and sends a CLOSE only where its REQ
  holds a slot.
- The socket going away drops the queue of that connection: `replayOn` sends every
  in-flight request through the gate again on the new socket.
- The timeout keeps running while queued.
- EVENT, AUTH and CLOSE are never queued. NEG-OPEN goes through `RelayManager.send`
  and stays outside the gate: strfry gives it a budget of its own. ndk sends no
  COUNT.

### Outcome

A queued request reports `pending` on its relay: the relay has not ended it.

A request that ends while still queued, on its timeout or on `close()`, never
reached the relay. It reports `notSent` with a new `RelayFailureKind.connectionFull`,
and `_outcomeOf` already checks `notSent` before `timedOut`.

A queued request whose connection `endRequestsOn` gives up stays `disconnected`:
the connection died, it was not full.

## Consequences

- A burst of REQs on one relay goes out as slots free up instead of being refused.
- When the provider answers slower than the socket opens, the first REQ on that
  connection waits for it, at most `SUBSCRIPTION_LIMIT_TIMEOUT`.
- Subscriptions hold their slot until closed. Once they fill their share, a new
  subscription waits for one of them to close, and the gate logs a warning. Without
  the gate, strfry would have sent it its stored events and then nothing.

## Tests

On a mock relay with a limit of `n`:

- `n + 1` queries: the last goes out after the first EOSE, never more than `n` open
- subscriptions past their EOSE keep their slots: once they fill their share, the
  next subscription waits while a query still goes out
- a subscription waiting on its share does not hold back a query queued after it
- `n + 1` sends in the same tick never exceed `n`
- closing a queued request writes no CLOSE and reports `notSent`
- a socket that drops and comes back replays at most `n`, then drains the rest
- a queued request that times out leaves the queue and reports `notSent` with
  `connectionFull`
- no REQ is written before the provider answers, and a provider that does not
  answer in time leaves the default
- a reconnection asks the provider again

## Alternative proposals

- Learn the limit from refusals. strfry refuses with a NOTICE that names no REQ and
  never with a CLOSED, so a refusal cannot be tied to a request. It publishes its
  limit in NIP-11 anyway.
- A `queued` value in `RelayRequestStatus`. One more value breaks the exhaustive
  switches of apps and needs a place in the collapse order, for what is mostly
  debugging.
