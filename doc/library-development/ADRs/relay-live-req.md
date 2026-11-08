# Architecture Decision Record: one live REQ per connection

Title: a subscription goes out alone, then, once its relay has answered EOSE,
listens through a REQ that its connection shares with the other subscriptions

## Context and Problem Statement

`Requests.subscription()` sends one REQ per subscription to each relay it routes
to, under the subscription's id. That REQ asks two things: the events the relay
stores, until its EOSE, and the events it receives afterwards.

A subscription holds a slot on each of its connections for as long as it lives
([relay-req-queue.md](relay-req-queue.md)). A screen showing a thread, its
reactions, its zaps and the profiles of its authors holds one subscription per
question. Once subscriptions fill their share of a connection, the next one waits
in the queue.

Two subscriptions share a REQ only when everything about them is identical
(`ConcurrencyCheck`). Merging different ones before their EOSE runs into the
stored part of the REQ: `limit` picks the newest events of each filter on the
relay, and `search` (NIP-50) leaves the matching to the relay. An EVENT names the
REQ it answers, not the filter, so the client cannot tell which subscription the
relay selected an event for.

After EOSE, `limit` no longer applies: NIP-01 makes it valid for the initial query
only. Every other field of a filter, `search` aside, is a test on the event that
the client can run exactly like the relay. Past its EOSE, a subscription's REQ is
worth the same filters with `limit: 0`, and those can share a REQ.

A relay does not always judge a filter the same way alone and next to others,
though. strfry (master) refuses a REQ with auth-required only when every filter
of it asks for restricted kinds only (`relay.auth.restrictedReadKinds`, `4, 1059`
by default, see
[RelayIngester.cpp](https://github.com/hoytech/strfry/blob/master/src/apps/relay/RelayIngester.cpp)).
It accepts a REQ that mixes them with other kinds, then drops each restricted
event, stored or new, for a socket that has not authenticated, without saying so
([ReadRestrictor.h](https://github.com/hoytech/strfry/blob/master/src/ReadRestrictor.h)).
It also sends its AUTH challenge only when it refuses a REQ. A DM subscription
merged with a notes subscription on an anonymous socket would get its EOSE, then
never a gift wrap. Since nothing refused it, `AuthPolicy.allow` would never move
it to a bound connection.

A new socket replays each subscription whole (`replayOn`). With `limit: n`, the
relay sends the newest `n` events again, and whatever the gap held beyond those
`n` is lost.

## Main Proposal

### Terms

- A short request ends on its EOSE: `Requests.query()`.
- A long request also wants what arrives after its EOSE: `Requests.subscription()`.
- Its own REQ: the REQ a subscription sends alone on a connection, as today.
- Its listener: its filters with `limit: 0`, for the new events.
- The live REQ of a connection: the REQ that carries the listeners of the
  subscriptions that moved there.

### Alone first

- A new subscription goes out as today: its own REQ on each relay, under its id,
  with its filters as given. The relay judges it alone, and what it answers
  follows today's rules, NIP-42 and `AuthPolicy` included.
- Once its own REQ has its EOSE on a connection, the relay has accepted its
  filters alone on that socket. Its listener may then move into the live REQ of
  that connection.
- A subscription with a `search` filter never moves, see Compaction.

The live REQ only ever carries filters the relay accepted alone on that socket,
`limit` aside.

### Moving into the live REQ

`RelayListeners`, new in ndk_core next to `RelayRequests`, keeps the live REQ of
each `RelayConnectionKey`:

- Moving a listener rewrites the live REQ: a new live REQ, under a new id,
  carries every listener of the connection, the newcomers included. Once it
  answers EOSE, the previous live REQ gets its CLOSE, and so does the own REQ of
  each listener it took in. Until then, both keep serving, so nothing is lost
  while the relay switches. An event that both bring is deduplicated by id.
- Moves that come while a rewrite waits for its EOSE go together into the next
  rewrite. A connection has at most one rewrite in flight, and a burst of EOSEs
  is batched by this rule alone.
- The filters of the live REQ have `limit: 0` and keep their own `since`, if they
  have one. `since: now` would drop events published late, gift wraps included:
  NIP-59 tweaks their `created_at` into the past, by up to two days in its sample
  code.
- The live REQ drops everything it receives before its EOSE. NIP-01 sends stored
  events before EOSE and new ones after, so a relay that honors `limit: 0` sends
  nothing there. A relay that reads it as "no limit", as ndk's own caches do, only
  costs bandwidth.
- Each event is verified once, then handed to the listeners whose filters it
  matches (`Filter.matches`), and to no other. An event that matches no listener
  is dropped.
- Listeners with different `AuthPolicy` values share the live REQ of an anonymous
  connection: nothing there is attributable, and a rewrite never triggers an AUTH.
- Its id is random. In debug mode it is `live-` followed by random hex (#716).

Removing a subscription:

- One still on its own REQ closes that REQ, as today.
- A listener stops getting events right away. Its filters leave the live REQ at
  the next rewrite, or after `LIVE_REQ_SHRINK_DELAY` if no rewrite comes first: a
  scrolling feed adds and removes subscriptions faster than rewrites are worth.
- When the last listener leaves, the live REQ is closed right away, so `hasWorkOn`
  lets the connection go.

### Slots

For the gate, own REQs and live REQs are all subscriptions. Together they stay
within the subscription share of [relay-req-queue.md](relay-req-queue.md), so they
never take the slots kept for queries, however many `search` subscriptions an app
opens.

A rewrite needs a second slot for one round trip. It may go one slot past the
share, since its EOSE gives back the previous live REQ and the own REQs it took
in. Without that, a burst of new subscriptions filling the share would wait for a
rewrite that waits for them. A rewrite never goes past the limit itself: without
a free slot it waits in the queue, and queries free theirs on EOSE. With one
rewrite per connection at a time, subscriptions hold at most one slot past their
share, for one round trip. A new live REQ, for an overflow, stays within the
share.

A connection whose limit is under 4 leaves no slot outside the share
(`limit ~/ 4` is 0), so a rewrite could wait forever there: its subscriptions
keep their own REQs.

### Compaction

The filters of the live REQ are those of its listeners:

1. Identical filters go out once. A filter is left out when another one matches
   everything it matches.
2. A live REQ carries at most `MAX_FILTERS_PER_LIVE_REQ` filters, and stays
   within the relay's NIP-11 `max_message_length`, or `DEFAULT_MAX_MESSAGE_LENGTH`
   when it is unknown. The listeners that do not fit go into a second live REQ on
   that connection.

Filters are never merged into new ones, such as the union of two `authors`
lists: a merged filter is one the relay never judged alone.

NIP-11 has no limit on the number of filters in one REQ. strfry accepts 200 by
default (`maxReqFilterSize`), and 3 when its `relay.filterValidation` is enabled
(`maxFiltersPerReq`). A relay that refuses a REQ for its size refuses the
rewrite, see Refusals.

A subscription with a `search` filter keeps its own REQ for its life. NIP-50 leaves
the matching to the relay, so the client cannot tell which of two searches an
event answers.

### Refusals

A rewrite is refused when the relay answers it with a CLOSED before its EOSE, or
when no EOSE comes within `LIVE_REQ_EOSE_TIMEOUT`, since some relays refuse with a
NOTICE that names no REQ. strfry answers a REQ it cannot take with
`CLOSED "bad req: ..."`.

- A refused rewrite changes nothing for the listeners: the previous live REQ and
  their own REQs were never closed.
- The connection then stops compacting until its socket is replaced. The
  subscriptions that have not moved yet keep their own REQs.
- A rewrite refused with auth-required is refused like any other. A rewrite never
  triggers an AUTH nor a move to a bound connection, so a subscription is never
  attributed because of another one.

A CLOSED after its EOSE ends the live REQ on that relay. Each of its listeners
then goes out alone again, as after a reconnection, and gets the answer the relay
gives it alone. The connection stops compacting until its socket is replaced.

### Reconnection

The live REQ is not replayed: what it proved belongs to the previous socket.
NIP-42 holds per socket, and strfry would accept a mixed REQ replayed before any
AUTH, then drop the restricted events without ever sending a challenge.

On the new socket:

- A subscription that never got its EOSE on that connection is replayed as today.
- Any other one goes out alone again. Each filter gets as `since` the time of the
  last message the previous socket received, minus `CATCH_UP_MARGIN`, unless its
  own `since` is later, and no `limit`: whatever it missed, it would have received
  live. That one REQ brings what the gap held, then the new events, and the relay
  guarantees nothing falls between them. After its EOSE, the listener moves again.
- The last message is the last moment the previous socket is known to have
  worked, since a socket can die without notice.
- A filter that can match a `kind:1059`, through its `kinds` or for lack of them,
  goes back `GIFT_WRAP_CATCH_UP_MARGIN` instead, because of the NIP-59 timestamps.

### Outcomes

A subscription reports on each relay what its own REQ reports there, as today.
Moving into the live REQ keeps its `eose`. A subscription sent out alone again,
after a reconnection or a CLOSED of the live REQ, reports what that REQ gets.

### API

`RelayReqs.subscribe()` opens a subscription that moves. It mirrors `RelayReq`:
`send(url, filters)`, `seal()`, `events`, `outcomes` and `close()`.
`Requests.subscription()` uses it, and keeps the cache read, the routing and
`ConcurrencyCheck` above it.

The id of a subscription stays the NIP-01 id of its own REQ. Once it has moved, its
new events come through the live REQ of the connection.

`RelayReqs.req(closeOnEose: false)` stays a raw REQ, sent under its id and never
moved. nip46 uses it.

### Client-side matching

`Filter.matches(Nip01Event)` joins ndk_nip01, with the NIP-01 semantics:

- `ids`, `authors` and `kinds` contain the event's field
- `since` and `until` bound `created_at`, both inclusive
- each `#x` contains the value at index 1 of one of the event's `x` tags,
  compared as given, case included

`limit` and `search` are not evaluated. `MockRelay._matches` already implements
this and moves there.

### Defaults

In `relay_defaults.dart`:

- `MAX_FILTERS_PER_LIVE_REQ`: 100, a value we chose under the 200 strfry accepts
  by default
- `DEFAULT_MAX_MESSAGE_LENGTH`: 65536 bytes, a value we chose for relays that
  publish no `max_message_length`
- `LIVE_REQ_EOSE_TIMEOUT`: 10 seconds
- `LIVE_REQ_SHRINK_DELAY`: 5 seconds
- `CATCH_UP_MARGIN`: 10 minutes, for the clock skew of the authors
- `GIFT_WRAP_CATCH_UP_MARGIN`: 2 days, from NIP-59

`max_message_length` reaches ndk_core the way the subscription limit does: a
`MessageLengthLimit` provider on `RelayManager`. `ndk` answers it from
`NdkConfig` first, then from the NIP-11 document that `Connectivity.getRelayInfo`
caches.

## Consequences

- A subscription is served alone until its EOSE: the same answer as today, the
  same NIP-42 behavior, the same id on the wire. Only its new events move.
- A relay that judges a filter differently next to others cannot hurt a
  subscription: the live REQ only carries filters it accepted alone on that
  socket. What it judges on the REQ as a whole, such as its size, refuses a
  rewrite, which stops compaction on that socket.
- The subscriptions that moved hold one slot per connection, or one per
  `MAX_FILTERS_PER_LIVE_REQ`. A subscription holds a slot of its own until it
  moves: a burst past the share waits, as today, then drains as subscriptions
  move.
- Moving costs a rewrite: no stored events, an immediate EOSE, and a second slot
  for one round trip.
- A reconnection costs one REQ per subscription, as today. Each one fetches what
  the gap missed instead of the newest events again.
- Once moved, a subscription no longer gets events that its filter does not match.
- Each live event is matched against every listener of its connection. An index by
  kind and author can come later, if profiling shows the need.
- `RelayReqs.req(closeOnEose: false)` and its users do not change.

## Tests

On a mock relay:

- a subscription goes out alone under its id and moves into the live REQ after
  its EOSE. Its own REQ closes once the live REQ answers EOSE, and an event the
  relay sends on it meanwhile still reaches the subscription
- `n` subscriptions that moved hold one slot on the relay, and each event reaches
  only the subscriptions whose filters match it
- a mock relay that restricts `kind:1059` like strfry: next to a notes
  subscription on the anonymous connection, a DM subscription with
  `AuthPolicy.allow` is refused alone, moves to the bound connection and gets new
  gift wraps there. The anonymous live REQ never carries its filter
- a subscription with a `search` filter never moves
- a relay that ignores `limit: 0`: what it sends before the EOSE of a live REQ
  reaches no listener
- moves that come while a rewrite waits for its EOSE go into one next rewrite
- removing a listener writes nothing before `LIVE_REQ_SHRINK_DELAY`, and the last
  listener leaving sends a CLOSE
- a rewrite refused with a CLOSED, or without an EOSE within
  `LIVE_REQ_EOSE_TIMEOUT`, leaves the previous live REQ and the own REQs open, and
  the connection stops compacting until a new socket
- with the share full of subscriptions waiting to move, the rewrite goes out one
  slot past it, then their own REQs close and the queued subscriptions go out
- a connection with a limit under 4 never compacts
- listeners past `MAX_FILTERS_PER_LIVE_REQ` or `max_message_length` go into a
  second live REQ
- after a reconnection, no live REQ is replayed. Each subscription that had moved
  goes out alone with `since` set to the last message minus `CATCH_UP_MARGIN` and
  no `limit`, then moves again after its EOSE. A `kind:1059` one goes back two
  days, and one that never got its EOSE is replayed as today
- a live REQ closed by the relay after its EOSE sends each of its listeners out
  alone again
- outcomes stay what the own REQ reported, across a move
- `Filter.matches` on the NIP-01 cases: tag values at index 1, case-sensitive,
  inclusive `since` and `until`

## Alternative proposals

- Splitting each subscription from the start into a query for its stored events
  and a listener in the shared REQ. The shared REQ then mixes filters the relay
  never judged alone. strfry accepts such a REQ where it would have refused the
  restricted filter alone, and drops its events without saying so: a DM
  subscription with `AuthPolicy.allow` would get no new DMs and never move to its
  bound connection. That split also needed the history written after the
  listener, which a relay processing the REQs of one socket out of order breaks.
- Rewriting under the same id. NIP-01 replaces a REQ sent again under its id, so
  no second slot is needed. But until the new EOSE, a stored event that a relay
  sends again looks like a new event of the previous filters. Dropping both loses
  new events, keeping both leaks stored ones.
- `since: now` instead of `limit: 0`. It loses what is published late, and gift
  wraps.
- Merging filters that differ in one field, such as two `authors` lists. It needs
  fewer filters, but sends filters the relay never judged alone. It may come later
  for relays known to judge only by event kind and socket.
- Replaying the live REQ on a new socket. It is cheaper, but what it proved
  belongs to the previous socket, as the strfry case shows.
- Merging short requests too, such as the `limit: 1` queries of `askReplaceable`.
  `limit` and `search` make it a different problem, for another ADR.
