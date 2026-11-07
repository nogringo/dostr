## 0.11.0-dev.2

 - Initial release, moved out of the `ndk` package.

### Coming from `ndk`

#### Imports and what moved

These files used to live in `ndk`. A deep import keeps its path and changes
package: `package:ndk/domain_layer/entities/relay.dart` is now
`package:ndk_core/domain_layer/entities/relay.dart`. `package:ndk/ndk.dart`
still exports what it did.

What lives under `lib/src` is internal. These files moved there and can no
longer be imported: `domain_layer/entities/nostr_message_raw.dart`,
`domain_layer/usecases/nip42/auth_event.dart`,
`shared/decode_nostr_msg/decode_nostr_msg.dart` and
`shared/nips/nip01/client_msg.dart`.

`IsolateManager` is in [`ndk_isolates`](https://pub.dev/packages/ndk_isolates):
`package:ndk/shared/isolates/isolate_manager.dart` is now
`package:ndk_isolates/ndk_isolates.dart`, which exports only `IsolateManager`
and `StreamComputeTask`. The pool no longer logs when it starts. When it fails
to start, the error still reaches every task that waits for it.

The logger is in [`ndk_logger`](https://pub.dev/packages/ndk_logger):
`package:ndk/shared/logger/*.dart` and `package:ndk/config/logger_defaults.dart`
are now `package:ndk_logger/ndk_logger.dart`, which
`package:ndk_core/ndk_core.dart` exports. `LogColor` is internal to it.

`Account`, `AccountType`, `AuthPolicy`, `AuthHandler` and `AuthAccounts` are in
[`ndk_signer`](https://pub.dev/packages/ndk_signer):
`package:ndk/domain_layer/entities/account.dart`, `auth_policy.dart`,
`auth_handler.dart` and
`package:ndk_core/domain_layer/repositories/auth_accounts.dart` are now
`package:ndk_signer/ndk_signer.dart`, which `package:ndk_core/ndk_core.dart`
exports. `TimeoutPausable` stays here, in
`package:ndk_core/domain_layer/entities/timeout_pausable.dart`.

`cleanRelayUrl` and `cleanRelayUrls`, the relay url normalization ndk_core
connects with, are in [`ndk_url_set`](https://pub.dev/packages/ndk_url_set):
`package:ndk/shared/helpers/relay_helper.dart` is now
`package:ndk_url_set/ndk_url_set.dart`, and `package:ndk_core/ndk_core.dart`
still exports them. `relayUrlRegex` and the url normalizer behind them are
internal to `ndk_url_set`.

`Bip340`, `Bip340EventSigner`, `Bip340EventVerifier` and `KeyPair` are in
[`ndk_bip340`](https://pub.dev/packages/ndk_bip340), and `Nip01Utils.signWithPrivateKey` is now
`Bip340.signEvent`. `Nip04` and `Nip44` are in
[`ndk_nip44`](https://pub.dev/packages/ndk_nip44).

`Nip01Event` and `EventVerifier` are in
[`ndk_nip01`](https://pub.dev/packages/ndk_nip01):
`package:ndk/domain_layer/entities/nip_01_event.dart` and
`package:ndk/domain_layer/repositories/event_verifier.dart` are now
`package:ndk_nip01/ndk_nip01.dart`, which `package:ndk_core/ndk_core.dart`
exports.
`EventKindClassification` and `Filter` are there too:
`package:ndk/shared/nips/nip01/event_kind_classification.dart` and
`package:ndk/domain_layer/entities/filter.dart` are now
`package:ndk_nip01/ndk_nip01.dart`.

`EventSigner`, `LocalEventSignerFactory`, `PendingSignerRequest`,
`SignerMethod`, `SignerRequestRejectedException` and
`SignerRequestCancelledException` are in
[`ndk_signer`](https://pub.dev/packages/ndk_signer):
`package:ndk/domain_layer/repositories/event_signer.dart`,
`package:ndk/domain_layer/entities/pending_signer_request.dart`,
`package:ndk/domain_layer/entities/signer_request_rejected_exception.dart` and
`package:ndk/domain_layer/entities/signer_request_cancelled_exception.dart` are
now `package:ndk_signer/ndk_signer.dart`, which
`package:ndk_core/ndk_core.dart` exports.

NIP-77 is in [`ndk_nip77`](https://pub.dev/packages/ndk_nip77), with
`NegentropyEncoder` and `Nip77Result`. `GlobalState` no longer has
`inFlightNegotiations`, `RelayManager` no longer has `onNegMsg`, `onNegErr` or
`onNegClosed`. A protocol of its own, NIP-77 included, plugs in with
`RelayManager.addProtocolHandler` and a `RelayProtocolHandler`.

`Tuple` and the `Helpers` of `ndk` are gone. `ndk_core` keeps a `Helpers` of
its own with only `getSecureRandomHex`, and `Nip01Event.secondsSinceEpoch()`
replaces `Helpers.now`. `MutexSimple` is in
`package:ndk_core/shared/helpers/mutex_simple.dart`. `castToListOfListOfString`
of `package:ndk/shared/helpers/list_casting.dart` is gone.

`ndk_core` makes no HTTP calls and does not read NIP-11 documents. `RelayInfo`,
`RelayInfoRepo` and `RelayInfoHttpRepoImpl` are in
[`ndk_nip11`](https://pub.dev/packages/ndk_nip11).
`HttpRequestDS` is in [`ndk_http`](https://pub.dev/packages/ndk_http):
`package:ndk/data_layer/data_sources/http_request.dart` is now
`package:ndk_http/ndk_http.dart`. `ndk.connectivity.getRelayInfo` fetches and
caches the documents, and the deprecated `RelayInfo.get` is gone.

`configureDefaultUserAgent`, which sets the User-Agent of the websockets of the
process on `dart:io`, is in `package:ndk_core/ndk_core.dart` instead of
`package:ndk/shared/net/user_agent.dart`. `NdkConfig.userAgent` still calls it.

`Nip13` is in [`ndk_nip13`](https://pub.dev/packages/ndk_nip13).
`Nip01Utils.isIdValid` checks the id alone and no longer rejects an event that
misses the proof-of-work target its `nonce` tag declares.
`Nip01Utils.createEventCalculateId`, `Nip01Utils.calculateEventId` and
`Nip01Utils.calculateEventIdSync` are gone: `Nip01Event` computes its own id,
and `payloadId` recomputes it from the payload.

#### Defaults

`RelayManager` no longer takes `bootstrapRelays` and no longer has
`seedRelaysConnected`: it opens no connection when it is built. Bootstrap
relays belong to `ndk`, where `NdkConfig` still defaults to
`DEFAULT_BOOTSTRAP_RELAYS` at its old path and `Ndk.bootstrapRelaysConnected`
replaces `ndk.relays.seedRelaysConnected`. `RequestDefaults` and
`BroadcastDefaults` keep only what `ndk_core` uses. `ndk` has both classes at
their old paths with everything else, including `DEFAULT_QUERY_TIMEOUT`,
`DEFAULT_USER_AGENT` and `MAX_INBOX_RELAYS_TO_BROADCAST`.

`connectTimeout`, on `RelayManager.connectRelay`, `RelayManager.openConnectionAs`,
`RelayPublish.send` and `RelayPublishSend` in `ndk`, is a `Duration` instead of a
number of seconds, and so is `DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT`.

#### `RelayManager`

`RelayManager` and `RelayConnectivity` are no longer generic.
`EngineAdditionalDataFactory`, `RelayConnectivity.specificEngineData` and
`RelayStats.touched` and `touchUseful` are gone: they only served the JIT
engine of `ndk`, which now keeps its data on its own.

`GlobalState` and `RequestState` are no longer public, in `ndk_core` or in
`ndk`: `RelayManager` keeps its own state and no longer takes a
`globalState`. Read its connections with `RelayManager.connectivities`, block
relays with `RelayManager.blockedRelays`, ask `RelayManager.isBroadcasting`
whether an event is still being broadcast, and `RelayReqs.openIds` which REQs
are open.

`RelayManager` keeps the plumbing behind `RelayReq` and broadcasts to itself.
`sendOrThrow`, `registerRelayRequest`, `registerRelayBroadcast`,
`failBroadcast`, `failRelayRequest`, `connectionForBroadcast`,
`isStillInFlight`, `beginPendingConnection`, `endPendingConnection`,
`sendRequestToRelay`, `sendCloseToRelay`, `sendCloseToConnection`,
`reSubscribeInFlightSubscriptions`, `updateRelayConnectivity`, `closeRequest`
and the deprecated `authenticateIfNeeded` are gone, and so is
`RequestState.registerRequest`. Send any message other than a REQ or an EVENT
with `RelayManager.send`, which now takes the `RelayConnectionKey` of a
connection and the message as a JSON array, such as
`['NEG-CLOSE', subscriptionId]`, instead of a `RelayConnectivity` and a
`ClientMsg`. `RelayManager.reconnectClosedConnections` reconnects and replays
the requests that `reSubscribeInFlightSubscriptions` used to replay by hand.

`RelayManager.connectRelay` returns a
`({bool connected, RelayFailure? failure})` record, with a null `failure` once
connected. It no longer takes an
`authPubkey` and only opens the anonymous connection: open one bound to an
identity with `RelayManager.openConnectionAs`, which asks the `AuthHandler`
first.

`isRelayConnecting`, `isConnectionConnecting`, `reconnectRelays` and the
`resetConnection` of a single connection are gone. A connection that is still
connecting has `relay.connecting` set in `RelayManager.connectivities`.
`authCallbackTimeout`, `authChallengeTimeout`, `authHandler` and
`nostrTransportFactory` are constructor parameters only, no longer fields.

`RelayConnectivity`, `Relay` and `RelayStats` are read-only: only
`RelayManager` changes them, and none has a public constructor anymore.
`RelayConnectivity` no longer has `relayTransport`, `listen` or `close`: read
`isConnected`, and close a connection with `RelayManager.closeConnection`.
`Relay` loses its setters, `tryingToConnect`, `succeededToConnect` and
`failedToConnect`. `RelayStats` loses its setters, `openRequestIds` and
`incStatsByNewEvent`, and its maps are unmodifiable. `eventsWritten` and
`dataWrittenBytes` are gone: nothing ever filled them.

A relay message that misses a field or carries one of the wrong type, and a
binary frame, are logged and dropped, and so is an exception a
`RelayProtocolHandler` throws. They used to escape as uncaught errors, which
end a plain Dart process.

`RelayManager.resetTransport` and `RelayManager.closeTransport` are now
`resetConnectionsTo` and `closeConnectionsTo`: they act on every connection to
the relay, anonymous or bound, where `isRelayConnected`, `reconnectRelay` and
`getRelayConnectivity` only look at the anonymous one.

#### Reconnecting

`RelayManager` is the only thing that reconnects, and a `NostrTransport` is a
single socket. `NostrTransportFactory` takes the url alone, without
`onReconnect` or `onDisconnect`. `ready` completes once the socket is open and
fails when it cannot connect or is closed first, instead of waiting forever.
The end of `listen` means the socket is gone.

A connection that drops is retried at once, then after a wait that doubles
from 500 milliseconds, for an hour. Its requests are replayed once it is back,
and given up as `disconnected` after that hour. `allowReconnect` set to false
now stops these retries: the transport used to retry on its own regardless. A
connection that drops within a minute of opening comes back too.
`WebSocketClientNostrTransportFactory` no longer takes `reconnectMaximumStep`:
`RelayManager` does, and `NdkConfig.webSocketReconnectMaximumStep` still sets
it.

`WebSocketNostrTransportFactory`, `WebSocketNostrTransport` and `WebsocketDS`
are gone: they reported a socket open before its handshake, which skipped the
connect timeout and kept `closeIdleConnections` from closing anything. Use
`WebSocketClientNostrTransportFactory`.

`reconnectClosedConnections` reconnects every connection at once instead of
one after the other. `authenticateConnection` answers false for a connection
that is not open.

`closeIdleConnections` no longer waits for the requests and broadcasts that
have yet to pick a relay. A REQ never sealed, or a publish never started or
failed, used to keep every connection open for good.

#### REQs

Open REQs with `RelayReqs`. Close one with `RelayReq.close`, by its id with
`RelayReqs.close`, or all of them with `RelayReqs.closeAll`.

`RelayReq.events` gives each event as a `RelayReqEvent`, with the relay that
sent it in `relayUrl`. It leaves the deprecated `Nip01Event.sources` empty;
`ndk` still fills it on the events `Requests` returns.

A subscription now reports `RelayRequestStatus.eose` on each relay that sent
its EOSE, instead of staying `pending` until it is closed. It still runs until
closed, and a CLOSED, a lost connection or its timeout replace that `eose`.

Closing a connection, with `closeConnection`, `closeConnectionsTo` or
`closeAllTransports`, ends the REQs still on it as `disconnected`, where they
used to stay `pending` until their timeout, or for good without one.

#### Publishes

`RelayManager.trackBroadcast` and `RelayManager.publishToRelay` are gone, and
`BroadcastState` is no longer public. `RelayBroadcastResponse` stays at its old
path. Publish a signed event with `RelayPublishes.publish`. To publish an event
that still has to be signed, open it with `RelayPublishes.open`: it counts as
in flight right away. Then `start` the `RelayPublish` with the signed event,
`send` it to each relay with an optional `veto` and `connectTimeout`, and
`seal` it, or `fail` it when signing does.

A `RelayPublish` reports like a `RelayReq`: `outcomes`, `outcomesStream` and
`done` give the `RelayBroadcastResponse` of each relay, keyed by relay url.
`NdkBroadcastResponse` stays in `ndk` at its old path, where `Broadcast` still
returns it, and `NdkBroadcastResponse.fromState` is gone.
`NetworkEngine.handleEventBroadcast` in `ndk` became `routeBroadcast`, which
gets the signed event and only picks its relays.

`considerDonePercent` counts the relays that accepted the event: a refusal no
longer brings a publish closer to done.

What `ndk_core` itself failed at comes as a `RelayFailure`, whose
`RelayFailureKind` says what it was and whose `detail` may say more, instead
of a sentence of its own in a message. `RelayRequestOutcome.failure` holds it
for `notSent`, `RelayBroadcastResponse.failure` for a relay the event did not
reach, and `connectRelay` returns it. `RelayRequestOutcome.message` and
`RelayBroadcastResponse.msg` only hold what the relay sent in its CLOSED or OK,
and a broadcast the relay refused for want of an identity it may not reveal
reports `RelayFailureKind.identityNotAllowed`, with the relay's message as its
`detail`. In `ndk`, the retry of pending deliveries reads that kind instead of
matching text.

#### Filters

An empty list in a `Filter` matches nothing, as NIP-01 requires, instead of
standing for an absent one. `toMap`, `fromMap` and `clone` keep `authors: []`,
where they used to drop it and leave a filter with no author constraint at
all. `Filter.matchesNothing` tells whether a filter can match any event.

`RelayReq.send` leaves out the filters that match nothing, and does not send to
a relay left with none. A REQ whose filters all match nothing ends right away,
with no relay in its outcomes. In `ndk`, `Requests` asks neither the cache nor
the relays for such a filter, and every cache manager reads and removes nothing
for an empty list, where it used to ignore it. An empty tag list no longer
means "has this tag".

#### Events

A `created_at` of 0 is kept. `Nip01Event` used to read it as "now", which
rewrote the `created_at` of an event received with 0 and made its id invalid.
Leave `createdAt` out to get the current time.

`Nip01Event.getTags`, `pTags`, `tTags` and `replyETags` return the values as
the event holds them, where they used to trim and lowercase them. The cache
managers of `ndk` still match tags regardless of case.

`Nip01Event.tags` is a copy of the tags the event was created with, and
neither it nor any of its tags can be changed: build another event with
`copyWith`. Changing the list an event was created from used to change its
tags without changing its id. `Metadata.tags` stays a list of its own, which
can be changed.

`copyWith` gives a copy whose `pubKey`, `createdAt`, `kind`, `tags` or
`content` changed the id of its new payload, and drops a `sig` that no longer
matches that id. It used to keep the old id and signature. Pass `id` to keep
another one, such as the id a remote signer chose.

`Nip01Event.validSig` is gone, from `copyWith` and the constructors too. A
request only hands out events whose id and signature it checked, and nothing
read the flag. The cache managers no longer store it.

`Nip01Event.kTextNodeKind` is now `kTextNoteKind`.

`Nip01Event` is a final class: it can no longer be extended, implemented or
mocked. Build the events a test needs with its constructor or `fromJson`.

`Nip01EventModel` is now a deprecated alias of `Nip01Event`, which has its
`fromJson`, `toJson` and `toJsonString`. `Nip01EventModel.fromEntity(event)`
is gone: use `event` itself. `toBase64()` is an extension member, in
`data_layer/models/nip_01_event_model.dart`.

`fromJson` is strict. It used to read a missing `pubkey` or `content` as `''`
and missing `tags` as none, to skip a tag that is not a list and to turn tag
values into strings: it now throws a `FormatException` for all of these, and
for a missing `created_at` or `kind` instead of a `TypeError`. A missing `id`,
which it read as `''`, is now computed. `Nip01Event.tryFromJson` returns null
where `fromJson` throws. `toJson` no longer writes `"sig": null` for an
unsigned event.

The other deprecated members are in `domain_layer/entities/nip_01_utils.dart`,
which `package:ndk_core/ndk_core.dart` exports: the event ones are extension
members of `Nip01Event`. `ndk_nip01` has none of them.

| Deprecated | Use |
| --- | --- |
| `Nip01Utils.isIdValid(event)` | `event.hasValidId` |
| `Nip01Utils.calculateId(event)` | `event.payloadId` |
| `event.getDtag()` | `event.dTag` |
| `event.getEId()` | `event.getFirstTag('e')` |
| `event.tTags` | `event.getTags('t')` |
| `event.replyETags` | the NIP-10 `reply` marker, read from `event.tags` |

`EventVerifier` is now an interface: implement it instead of extending it.
