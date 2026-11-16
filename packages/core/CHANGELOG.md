## 0.1.0

 - Initial release, moved out of the `ndk` package.

### Coming from `ndk`

#### Imports and what moved

These files used to live in `ndk`.
Every file of `dostr_core` is under `lib/src` and can no longer be imported on its own: a deep import such as `package:ndk/domain_layer/entities/relay.dart` or `package:ndk/config/request_defaults.dart` is now `package:dostr_core/dostr_core.dart`.
What it does not export is internal: `NostrMessageRaw`, `decodeNostrMsg`, `ClientMsg`, `VerifyEventStream`, `verifyEvent` and `VerifiedEventMemCache`.
`domain_layer/usecases/nip42/auth_event.dart` is gone: `RelayManager` builds the AUTH event itself.

`IsolateManager` and its pool are gone: relay messages are decoded on the main isolate, and `Isolate.run` replaces `runInComputeIsolate` for your own work.

`package:ndk/shared/logger/*.dart` and `package:ndk/config/logger_defaults.dart` are now `package:dostr_core/dostr_core.dart`.
`NdkLogger` became `DostrLogger`, and `LogColor` is internal.

`Account`, `AccountType`, `AuthPolicy`, `AuthHandler` and `AuthAccounts` are in [`dostr_signer`](https://pub.dev/packages/dostr_signer): `package:ndk/domain_layer/entities/account.dart`, `auth_policy.dart` and `auth_handler.dart` are now `package:dostr_signer/dostr_signer.dart`, which `package:dostr_core/dostr_core.dart` exports.
`TimeoutPausable` moved from `auth_handler.dart` to `package:dostr_core/dostr_core.dart`.

`cleanRelayUrl` and `cleanRelayUrls`, the relay url normalization dostr_core connects with, are in [`dostr_relay_url`](https://pub.dev/packages/dostr_relay_url): `package:ndk/shared/helpers/relay_helper.dart` is now `package:dostr_relay_url/dostr_relay_url.dart`, and `package:dostr_core/dostr_core.dart` exports them.
`relayUrlRegex` and the url normalizer behind them are gone: `cleanRelayUrl` builds on `Uri.parse`.

`Bip340`, `Bip340EventVerifier` and `KeyPair` are in [`dostr_bip340`](https://pub.dev/packages/dostr_bip340), and so are `Bip340EventSigner` and `Bip340EventSignerFactory`, now `Bip340Signer` and `Bip340SignerFactory`.
`Nip01Utils.signWithPrivateKey` is now `Bip340.signEvent`.
`Nip04` and `Nip44` are in [`dostr_nip44`](https://pub.dev/packages/dostr_nip44).

`Nip01Event` and `EventVerifier` are in [`dostr_nip01`](https://pub.dev/packages/dostr_nip01): `package:ndk/domain_layer/entities/nip_01_event.dart` and `package:ndk/domain_layer/repositories/event_verifier.dart` are now `package:dostr_nip01/dostr_nip01.dart`, which `package:dostr_core/dostr_core.dart` exports.
`EventKindClassification` and `Filter` are there too: `package:ndk/shared/nips/nip01/event_kind_classification.dart` and `package:ndk/domain_layer/entities/filter.dart` are now `package:dostr_nip01/dostr_nip01.dart`.

`EventSigner` is now `NostrSigner`, and `LocalEventSignerFactory` is now `LocalSignerFactory`, since a signer also encrypts and decrypts.
They are in [`dostr_signer`](https://pub.dev/packages/dostr_signer) with `PendingSignerRequest`, `SignerMethod`, `SignerRequestRejectedException` and `SignerRequestCancelledException`: `package:ndk/domain_layer/repositories/event_signer.dart`, `package:ndk/domain_layer/entities/pending_signer_request.dart`, `package:ndk/domain_layer/entities/signer_request_rejected_exception.dart` and `package:ndk/domain_layer/entities/signer_request_cancelled_exception.dart` are now `package:dostr_signer/dostr_signer.dart`, which `package:dostr_core/dostr_core.dart` exports.
`encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey` instead of `recipientPubKey` and `senderPubKey`.
`encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, with the named parameters of the NIP-44 methods, and the four of them return a `Future<String>` instead of a `Future<String?>`: a signer that cannot encrypt or decrypt throws.
`canSign` is a getter, and `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone.
`NostrSigner` and `LocalSignerFactory` are interface classes: a signer implements them and inherits nothing.
`Account` reads its pubkey from its signer, so its constructor no longer takes `pubkey`.
`SignerMethod` no longer has `connect` or `protocolString`.

NIP-77 is in [`dostr_nip77`](https://pub.dev/packages/dostr_nip77), with `NegentropyEncoder` and `Nip77Result`.
`GlobalState` no longer has `inFlightNegotiations`, `RelayManager` no longer has `onNegMsg`, `onNegErr` or `onNegClosed`.
A protocol of its own, NIP-77 included, plugs in with `RelayManager.addProtocolHandler` and a `RelayProtocolHandler`.

`Tuple`, `Helpers` and `MutexSimple` are gone: use `DateTime.now().millisecondsSinceEpoch ~/ 1000` for `Helpers.now`.
`castToListOfListOfString` of `package:ndk/shared/helpers/list_casting.dart` is gone.

`dostr_core` makes no HTTP calls and does not read NIP-11 documents.
`RelayInfo` is in [`dostr_nip11`](https://pub.dev/packages/dostr_nip11), `RelayInfoRepo` is its `RelayInfoRepository`, and `RelayInfoHttpRepoImpl(httpDS: http)` is its `HttpRelayInfoRepository(client)`, which takes an `http.Client`.
`HttpRequestDS` is gone: the packages that make HTTP calls take an `http.Client`.
The deprecated `RelayInfo.get` is gone.

`configureDefaultUserAgent`, which sets the User-Agent of the websockets of the process on `dart:io`, is in `package:dostr_core/dostr_core.dart` instead of `package:ndk/shared/net/user_agent.dart`.

`Nip13` is in [`dostr_nip13`](https://pub.dev/packages/dostr_nip13).
`Nip01Utils.isIdValid` checks the id alone and no longer rejects an event that misses the proof-of-work target its `nonce` tag declares.
`Nip01Utils.createEventCalculateId`, `Nip01Utils.calculateEventId` and `Nip01Utils.calculateEventIdSync` are gone: `Nip01Event` computes its own id, and `payloadId` recomputes it from the payload.

#### Defaults

`RelayManager` no longer takes `bootstrapRelays` and no longer has `seedRelaysConnected`: it opens no connection when it is built.
`dostr_core` has no `DEFAULT_BOOTSTRAP_RELAYS`.
Nothing replaces `ndk.relays.seedRelaysConnected`.
`RequestDefaults` and `BroadcastDefaults` are gone.
What `dostr_core` uses of them is a top-level constant, and the rest is gone: `DEFAULT_QUERY_TIMEOUT`, `DEFAULT_USER_AGENT` and `MAX_INBOX_RELAYS_TO_BROADCAST`, among others.

`connectTimeout`, on `RelayManager.connectRelay`, `RelayManager.openConnectionAs` and `RelayPublish.send`, is a `Duration` instead of a number of seconds, and so is `defaultWebSocketConnectTimeout`.

The default constants are in lowerCamelCase: `DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT` is `defaultWebSocketConnectTimeout`, `RequestDefaults.DEFAULT_AUTH_CALLBACK_TIMEOUT` is `defaultAuthCallbackTimeout`, `BroadcastDefaults.TIMEOUT` is `defaultBroadcastTimeout` and `BroadcastDefaults.CONSIDER_DONE_PERCENT` is `defaultConsiderDonePercent`.
`RX_REPLAYSUBJECT_MAX_EVENTS`, which nothing read, is gone.

#### `RelayManager`

`RelayManager` and `RelayConnectivity` are no longer generic.
`EngineAdditionalDataFactory`, `RelayConnectivity.specificEngineData` and `RelayStats.touched` and `touchUseful` are gone: they only served the JIT engine of `ndk`.

`GlobalState` and `RequestState` are no longer public: `RelayManager` keeps its own state and no longer takes a `globalState`.
Read its connections with `RelayManager.connectivities`, block relays with `RelayManager.blockedRelays`, ask `RelayManager.isBroadcasting` whether an event is still being broadcast, and `RelayReqs.openIds` which REQs are open.

`RelayManager` keeps the plumbing behind `RelayReq` and broadcasts to itself.
`sendOrThrow`, `registerRelayRequest`, `registerRelayBroadcast`, `failBroadcast`, `failRelayRequest`, `connectionForBroadcast`, `isStillInFlight`, `beginPendingConnection`, `endPendingConnection`, `sendCloseToRelay`, `sendCloseToConnection`, `reSubscribeInFlightSubscriptions`, `updateRelayConnectivity` and the deprecated `authenticateIfNeeded` are gone, and so is `RequestState.registerRequest`.
Send any message other than a REQ or an EVENT with `RelayManager.send`, which now takes the `RelayConnectionKey` of a connection and the message as a JSON array, such as `['NEG-CLOSE', subscriptionId]`, instead of a `RelayConnectivity` and a `ClientMsg`.
`RelayManager.reconnectClosedConnections` reconnects and replays the requests that `reSubscribeInFlightSubscriptions` used to replay by hand.

`RelayManager.connectRelay` returns a `({bool connected, RelayFailure? failure})` record, with a null `failure` once connected.
It no longer takes an `authPubkey` and only opens the anonymous connection: open one bound to an identity with `RelayManager.openConnectionAs`, which asks the `AuthHandler` first.

`isRelayConnecting`, `isConnectionConnecting`, `reconnectRelays` and the `resetConnection` of a single connection are gone.
A connection that is still connecting has `relay.connecting` set in `RelayManager.connectivities`.
`authCallbackTimeout`, `authChallengeTimeout`, `authHandler` and `nostrTransportFactory` are constructor parameters only, no longer fields.

`RelayConnectivity`, `Relay` and `RelayStats` are read-only: only `RelayManager` changes them, and none has a public constructor anymore.
`RelayConnectivity` no longer has `relayTransport`, `listen` or `close`: read `isConnected`, and close a connection with `RelayManager.closeConnection`.
`Relay` loses its setters, `tryingToConnect`, `succeededToConnect` and `failedToConnect`.
`RelayStats` loses its setters, `openRequestIds` and `incStatsByNewEvent`, and its maps are unmodifiable.
`eventsWritten` and `dataWrittenBytes` are gone: nothing ever filled them.

A relay message that misses a field or carries one of the wrong type, and a binary frame, are logged and dropped, and so is an exception a `RelayProtocolHandler` throws.
They used to escape as uncaught errors, which end a plain Dart process.

`RelayManager.resetTransport` and `RelayManager.closeTransport` are now `resetConnectionsTo` and `closeConnectionsTo`: they act on every connection to the relay, anonymous or bound, where `isRelayConnected`, `reconnectRelay` and `getRelayConnectivity` only look at the anonymous one.

#### Relay urls

The relay urls `dostr_core` takes and gives are `RelayUrl`s, from [`dostr_relay_url`](https://pub.dev/packages/dostr_relay_url): normalized urls, as an extension type on `String`, so code that reads one as a `String` keeps working.
Make one with `RelayUrl.parse`, which throws a `FormatException` for a url that is not a relay's, or with `cleanRelayUrl`, which returns null.

 - `RelayManager.isRelayConnected`, `reconnectRelay`, `resetConnectionsTo`, `closeConnectionsTo`, `getRelayConnectivity` and `openConnectionAs` take a `RelayUrl`. `connectRelay` still takes a `dirtyUrl`, which it normalizes.
 - `RelayManager.blockedRelays` is a `Set<RelayUrl>`, so a relay added in another spelling is blocked too.
 - `RelayConnectionKey.anonymous`, `RelayConnectionKey.authenticated` and `RelayConnectionKey.forAuth` take a `RelayUrl` and no longer normalize it.
 - `RelayReq.send`, `RelayPublish.send`, `RelayPublishes.publish` and the `relays` of `RelayReqs.req` take `RelayUrl`s.
 - `RelayConnectivity.url`, `Relay.url`, `RelayReqEvent.relayUrl` and `RelayBroadcastResponse.relayUrl` are `RelayUrl`s, and so are the keys of `RelayReq.outcomes` and `RelayPublish.outcomes`.
 - `NostrTransportFactory`, `SubscriptionLimit`, `MessageLengthLimit` and `onMessageLengthLearned` are given a `RelayUrl`. One written for a `String` still fits.
 - `WebSocketClientNostrTransportFactory` no longer throws on a url it cannot parse, since it is given a `RelayUrl`.

#### Reconnecting

`RelayManager` is the only thing that reconnects, and a `NostrTransport` is a single socket.
`NostrTransportFactory` takes the url alone, without `onReconnect` or `onDisconnect`.
`ready` completes once the socket is open and fails when it cannot connect or is closed first, instead of waiting forever.
The end of `listen` means the socket is gone.

A connection that drops is retried at once, then after a wait that doubles from 500 milliseconds, for an hour.
Its requests are replayed once it is back, and given up as `disconnected` after that hour.
`allowReconnect` set to false now stops these retries: the transport used to retry on its own regardless.
A connection that drops within a minute of opening comes back too.
One that carries nothing `closeIdleConnections` would keep is forgotten instead, when it drops or before an attempt to bring it back: a relay that closes idle sockets used to get them reopened forever.
`WebSocketClientNostrTransportFactory` no longer takes `reconnectMaximumStep`: `RelayManager` does.

#### Idle connections

A connection is closed once it went without work, as `closeIdleConnections` counts it, and without any message sent or received, for `anonymousIdleTimeout` (a minute by default) or, when it is bound to an identity, `authenticatedIdleTimeout` (five minutes by default).
Connections used to stay open until they were closed explicitly.
Null keeps them open.

`WebSocketNostrTransportFactory`, `WebSocketNostrTransport` and `WebsocketDS` are gone: they reported a socket open before its handshake, which skipped the connect timeout and kept `closeIdleConnections` from closing anything.
Use `WebSocketClientNostrTransportFactory`.

`WebsocketDSClient` is gone too, and `WebSocketClientNostrTransport` takes a `WebSocketChannel` from `web_socket_channel`: the transport no longer runs on a copy of `web_socket_client`.

`reconnectClosedConnections` reconnects every connection at once instead of one after the other.
`authenticateConnection` answers false for a connection that is not open.

`closeIdleConnections` no longer waits for the requests and broadcasts that have yet to pick a relay.
A REQ never sealed, or a publish never started or failed, used to keep every connection open for good.

#### REQs

Open REQs with `RelayReqs`.
Close one with `RelayReq.close`, by its id with `RelayReqs.close`, or all of them with `RelayReqs.closeAll`.

`RelayReq.events` gives each event as a `RelayReqEvent`, with the relay that sent it in `relayUrl`.
The deprecated `Nip01Event.sources` is gone.

`EventFilter` is gone, since no request takes one any more: filter `RelayReq.events` with `where`.

A subscription now reports `RelayRequestStatus.eose` on each relay that sent its EOSE, instead of staying `pending` until it is closed.
It still runs until closed, and a CLOSED, a lost connection or its timeout replace that `eose`.

Closing a connection, with `closeConnection`, `closeConnectionsTo` or `closeAllTransports`, ends the REQs still on it as `disconnected`, where they used to stay `pending` until their timeout, or for good without one.

#### Publishes

`BroadcastState` is no longer public, and `RelayBroadcastResponse` is in `package:dostr_core/dostr_core.dart`.
Publish a signed event with `RelayPublishes.publish`.
To publish an event that still has to be signed, open it with `RelayPublishes.open`: it counts as in flight right away.
Then `start` the `RelayPublish` with the signed event, `send` it to each relay with an optional `veto` and `connectTimeout`, and `seal` it, or `fail` it when signing does.

A `RelayPublish` reports like a `RelayReq`: `outcomes`, `outcomesStream` and `done` give the `RelayBroadcastResponse` of each relay, keyed by relay url.

`considerDonePercent` counts the relays that accepted the event: a refusal no longer brings a publish closer to done.

What `dostr_core` itself failed at comes as a `RelayFailure`, whose `RelayFailureKind` says what it was and whose `detail` may say more, instead of a sentence of its own in a message.
`RelayRequestOutcome.failure` holds it for `notSent`, `RelayBroadcastResponse.failure` for a relay the event did not reach, and `connectRelay` returns it.
`RelayRequestOutcome.message` and `RelayBroadcastResponse.msg` only hold what the relay sent in its CLOSED or OK, and a broadcast the relay refused for want of an identity it may not reveal reports `RelayFailureKind.identityNotAllowed`, with the relay's message as its `detail`.

#### Filters

An empty list in a `Filter` matches nothing, as NIP-01 requires, instead of standing for an absent one.
`toJson`, `fromJson` and `clone` keep `authors: []`, where they used to drop it and leave a filter with no author constraint at all.
`Filter.matchesNothing` tells whether a filter can match any event.

`Filter.toMap` and `Filter.fromMap` are now `toJson` and `fromJson`, as in `Nip01Event`.
`fromJson` is strict: a field of the wrong type throws a `FormatException` instead of a `TypeError`, and `Filter.tryFromJson` returns null where it throws.
`fromJson`, `setTag` and `getTag` take a tag name of any length, where they used to ignore the longer ones.

`Filter.cloneWithAuthors`, `cloneWithPTags` and `mergeAuthors` are gone: use `filter.clone()..authors = authors`, `filter.clone()..setTag('p', pTags)` and `a.clone()..authors = {...a.authors!, ...b.authors!}.toList()`.

`Filter.tTags` and `mTags` are gone, from the constructor too: use `getTag('t')` and `tags: {'t': hashtags}`.

`Filter.clone` copies the values of the tag filters too, which it used to share with the original filter.

`RelayReq.send` leaves out the filters that match nothing, and does not send to a relay left with none.
A REQ whose filters all match nothing ends right away, with no relay in its outcomes.
An empty tag list no longer means "has this tag".

#### Events

A `created_at` of 0 is kept.
`Nip01Event` used to read it as "now", which rewrote the `created_at` of an event received with 0 and made its id invalid.
Leave `createdAt` out to get the current time.

`Nip01Event.getTags`, `pTags`, `tTags` and `replyETags` return the values as the event holds them, where they used to trim and lowercase them.

`Nip01Event.tags` is a copy of the tags the event was created with, and neither it nor any of its tags can be changed: build another event with `copyWith`.
Changing the list an event was created from used to change its tags without changing its id.

`copyWith` gives a copy whose `pubkey`, `createdAt`, `kind`, `tags` or `content` changed the id of its new payload, and drops a `sig` that no longer matches that id.
It used to keep the old id and signature.
Pass `id` to keep another one, such as the id a remote signer chose.

`Nip01Event.validSig` is gone, from `copyWith` and the constructors too.
A request only hands out events whose id and signature it checked, and nothing read the flag.

`Nip01Event.pubKey` is now `pubkey`, the name NIP-01 gives the field.

`Nip01Event.kTextNodeKind` is now `kTextNoteKind`.

`Nip01Event.secondsSinceEpoch()` is gone: leave `createdAt` out to get the current time.

`EventKindClassification.isParameterizedReplaceableKind` is gone: use `isAddressableKind`, the name NIP-01 now gives these kinds.
`isRegularReplaceableKind` and `legacyReplaceableKinds` are gone too: `isReplaceableKind` covers them.
`EventKindClassification` only has static members, and can no longer be instantiated or extended.

`Nip01Event` is a final class: it can no longer be extended, implemented or mocked.
Build the events a test needs with its constructor or `fromJson`.

`Nip01EventModel` is gone: use `Nip01Event`, which has its `fromJson`, `toJson` and `toJsonString`, and `event` itself instead of `Nip01EventModel.fromEntity(event)`.
`toBase64()` is an extension member, which `package:dostr_core/dostr_core.dart` exports.

`fromJson` is strict.
It used to read a missing `pubkey` or `content` as `''` and missing `tags` as none, to skip a tag that is not a list and to turn tag values into strings: it now throws a `FormatException` for all of these, and for a missing `created_at` or `kind` instead of a `TypeError`.
A missing `id`, which it read as `''`, is now computed.
`Nip01Event.tryFromJson` returns null where `fromJson` throws.
`toJson` no longer writes `"sig": null` for an unsigned event.

The other deprecated members are in `package:dostr_core/dostr_core.dart`: the event ones are extension members of `Nip01Event`.
`dostr_nip01` has none of them.

| Deprecated | Use |
| --- | --- |
| `Nip01Utils.isIdValid(event)` | `event.hasValidId` |
| `Nip01Utils.calculateId(event)` | `event.payloadId` |
| `event.getDtag()` | `event.dTag` |
| `event.getEId()` | `event.getFirstTag('e')` |
| `event.tTags` | `event.getTags('t')` |
| `event.replyETags` | the NIP-10 `reply` marker, read from `event.tags` |

`EventVerifier` is now an interface: implement it instead of extending it.
