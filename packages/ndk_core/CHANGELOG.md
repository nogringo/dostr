## 0.11.0-dev.2

 - Initial release, moved out of the `ndk` package.

### Coming from `ndk`

#### Imports and what moved

These files used to live in `ndk`. A deep import keeps its path and changes
package: `package:ndk/domain_layer/entities/filter.dart` is now
`package:ndk_core/domain_layer/entities/filter.dart`. `package:ndk/ndk.dart`
still exports what it did.

What lives under `lib/src` is internal. These files moved there and can no
longer be imported: `domain_layer/entities/nostr_message_raw.dart`,
`domain_layer/usecases/nip42/auth_event.dart`,
`shared/decode_nostr_msg/decode_nostr_msg.dart`,
`shared/helpers/url_normalizer.dart`, `shared/logger/log_color.dart`,
`shared/nips/nip01/client_msg.dart`, and the two implementations behind
`shared/isolates/isolate_manager.dart`, which still imports as before.

`Bip340`, `Bip340EventSigner`, `Bip340EventVerifier` and `KeyPair` are in
[`ndk_bip340`](https://pub.dev/packages/ndk_bip340), and `Nip01Utils.signWithPrivateKey` is now
`Bip340.signEvent`. `Nip04` and `Nip44` are in
[`ndk_nip44`](https://pub.dev/packages/ndk_nip44).

NIP-77 is in [`ndk_nip77`](https://pub.dev/packages/ndk_nip77), with
`NegentropyEncoder` and `Nip77Result`. `GlobalState` no longer has
`inFlightNegotiations`, `RelayManager` no longer has `onNegMsg`, `onNegErr` or
`onNegClosed`. A protocol of its own, NIP-77 included, plugs in with
`RelayManager.addProtocolHandler` and a `RelayProtocolHandler`.

`Helpers`, `Tuple` and `EventKindClassification` stay in `ndk` at their old
paths. `ndk_core` keeps a `Helpers` of its own with only `getSecureRandomHex`.

`ndk_core` makes no HTTP calls and does not read NIP-11 documents. `RelayInfo`,
`RelayInfoRepo`, `HttpRequestDS` and `RelayInfoHttpRepoImpl` stay in `ndk` at
their old paths. `ndk.connectivity.getRelayInfo` fetches and caches the
documents, and the deprecated `RelayInfo.get` is gone.

`Nip13` stays in `ndk` at its old path. `Nip01Utils.isIdValid` checks the id
alone and no longer rejects an event that misses the proof-of-work target its
`nonce` tag declares. `Nip01Utils.createEventCalculateId` and
`Nip01Utils.calculateEventId` are gone: `Nip01Event` computes its own id.

#### Defaults

`RelayManager` connects to no relay unless you pass `bootstrapRelays`.
`DEFAULT_BOOTSTRAP_RELAYS` stays in `ndk` at its old path, and `NdkConfig`
still defaults to it. `RequestDefaults` and `BroadcastDefaults` keep only what
`ndk_core` uses. `ndk` has both classes at their old paths with everything
else, including `DEFAULT_QUERY_TIMEOUT`, `DEFAULT_USER_AGENT` and
`MAX_INBOX_RELAYS_TO_BROADCAST`.

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

`RelayManager.connectRelay` returns a `({bool connected, String? error})`
record, with a null `error` once connected. It no longer takes an
`authPubkey` and only opens the anonymous connection: open one bound to an
identity with `RelayManager.openConnectionAs`, which asks the `AuthHandler`
first.

`isRelayConnecting`, `isConnectionConnecting`, `reconnectRelays` and the
`resetConnection` of a single connection are gone. A connection that is still
connecting has `relay.connecting` set in `RelayManager.connectivities`.
`authCallbackTimeout`, `authChallengeTimeout`, `authHandler` and
`nostrTransportFactory` are constructor parameters only, no longer fields.

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
