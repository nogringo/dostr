# Coming from `ndk`

Dostr started as the `ndk` package, now split into the packages listed in the [README](../README.md#monorepo-packages).
This page is for code that used `ndk`: where each part moved, and what changed on the way.
The relay code is in [`dostr_core`](../packages/core/README.md), `Nip01Event` and `Filter` in [`dostr_nip01`](../packages/nip01/README.md), and the signers in [`dostr_signer`](../packages/signer/README.md).

## Imports and what moved

Every file of `dostr_core` is under `lib/src` and can no longer be imported on its own: a deep import such as `package:ndk/domain_layer/entities/relay.dart` or `package:ndk/config/request_defaults.dart` is now `package:dostr_core/dostr_core.dart`.
`NostrMessageRaw`, `decodeNostrMsg`, `ClientMsg`, `verifyEvent` and `VerifiedEventMemCache` are no longer public.
`VerifyEventStream` is gone: `RelayReq.events` verifies its events itself.
`domain_layer/usecases/nip42/auth_event.dart` is gone: `RelayManager` builds the AUTH event itself.

`IsolateManager` and its pool are gone: relay messages are decoded on the main isolate, and `Isolate.run` replaces `runInComputeIsolate` for your own work.

The logger of `ndk` is gone, with `package:ndk/shared/logger/*.dart` and `package:ndk/config/logger_defaults.dart`.
`dostr_core` logs with [`logging`](https://pub.dev/packages/logging), under the name `dostr_core`, and prints nothing until the app listens to `Logger.root.onRecord`.
`Logger.setLogLevel(level)` is now `Logger.root.level = level`, with the levels of `logging`.
A relay that cannot be reached, a socket error, an OK false, a CLOSED and a NOTICE are no longer logged as errors: they are part of talking to relays, and the outcomes report them.
`severe` is left to a bug of `dostr_core` or of the app, and `warning` to a relay that misbehaves or a callback of the app that throws.

`AuthPolicy`, `AuthHandler` and `AuthAccounts` are in [`dostr_signer`](https://pub.dev/packages/dostr_signer): `package:ndk/domain_layer/entities/auth_policy.dart` and `auth_handler.dart` are now `package:dostr_signer/dostr_signer.dart`, which `package:dostr_core/dostr_core.dart` exports.
`Account`, from `package:ndk/domain_layer/entities/account.dart`, is gone: an account is its `NostrSigner`. `AuthPolicy.allow` and `AuthPolicy.require` take the signer, `AuthPolicy.account` is now `signer`, and `AuthAccounts` gives signers, with `getAccount(pubkey)` instead of the `accounts` map.
`RelayManager.openConnectionAs` and `accountForAuth` take or return a `NostrSigner` too.
`TimeoutPausable` moved from `auth_handler.dart` to `package:dostr_core/dostr_core.dart`.
`AuthPolicy` no longer has `canonical`, `==` or `hashCode`.

The relay url normalization dostr_core connects with is in [`dostr_relay_url`](https://pub.dev/packages/dostr_relay_url): `package:ndk/shared/helpers/relay_helper.dart` is now `package:dostr_relay_url/dostr_relay_url.dart`, which `package:dostr_core/dostr_core.dart` exports.
`cleanRelayUrl(url)` is now `RelayUrl.tryParse(url)`, and `cleanRelayUrls(urls)` is gone: `urls.map(RelayUrl.tryParse).nonNulls` replaces it.
`relayUrlRegex` and the url normalizer behind them are gone: `RelayUrl.tryParse` builds on `Uri.parse`.

`Bip340`, `Bip340EventVerifier` and `KeyPair` are in [`dostr_bip340`](https://pub.dev/packages/dostr_bip340), and so are `Bip340EventSigner` and `Bip340EventSignerFactory`, now `Bip340Signer` and `Bip340SignerFactory`.
`Nip01Utils.signWithPrivateKey` is now `Bip340.signEvent`.
`Nip04` and `Nip44` are in [`dostr_nip44`](https://pub.dev/packages/dostr_nip44).

`Nip01Event` and `EventVerifier` are in [`dostr_nip01`](https://pub.dev/packages/dostr_nip01): `package:ndk/domain_layer/entities/nip_01_event.dart` and `package:ndk/domain_layer/repositories/event_verifier.dart` are now `package:dostr_nip01/dostr_nip01.dart`, which `package:dostr_core/dostr_core.dart` exports.
`EventKindClassification` and `Filter` are there too: `package:ndk/shared/nips/nip01/event_kind_classification.dart` and `package:ndk/domain_layer/entities/filter.dart` are now `package:dostr_nip01/dostr_nip01.dart`.

`EventSigner` is now `NostrSigner`, and `LocalEventSignerFactory` is now `LocalSignerFactory`, since a signer also encrypts and decrypts.
They are in [`dostr_signer`](https://pub.dev/packages/dostr_signer) with `PendingSignerRequest`, `SignerRequestRejectedException` and `SignerRequestCancelledException`: `package:ndk/domain_layer/repositories/event_signer.dart`, `package:ndk/domain_layer/entities/pending_signer_request.dart`, `package:ndk/domain_layer/entities/signer_request_rejected_exception.dart` and `package:ndk/domain_layer/entities/signer_request_cancelled_exception.dart` are now `package:dostr_signer/dostr_signer.dart`, which `package:dostr_core/dostr_core.dart` exports.
`encryptNip44` and `decryptNip44` take `recipientPubkey` and `senderPubkey` instead of `recipientPubKey` and `senderPubKey`.
`encrypt` and `decrypt` are now `encryptNip04` and `decryptNip04`, with the named parameters of the NIP-44 methods, and the four of them return a `Future<String>` instead of a `Future<String?>`: a signer that cannot encrypt or decrypt throws.
`canSign` is a getter, `getPublicKey()` is the `publicKey` getter, and `requiresInteractiveSigning`, `requiresSignerNetwork` and `signerTransportRelayUrls` are gone.
`NostrSigner` and `LocalSignerFactory` are interface classes: a signer implements them and inherits nothing.
`LocalSignerFactory.create` takes the private key alone, `readOnly` takes a public key, and `derivePublicKey` is gone.
`SignerRequestRejectedException`, `SignerRequestCancelledException` and the new `SignerRequestFailedException` are all a `SignerRequestException`.
`NostrSigner` says what a signer throws, and that `publicKey` never throws: the [`dostr_signer` changelog](https://pub.dev/packages/dostr_signer/changelog) has the details.
`PendingSignerRequest` is a sealed class, a `PendingSignRequest`, `PendingEncryptRequest` or `PendingDecryptRequest`, and `SignerMethod` is gone: the `scheme` of an encryption or a decryption, an `EncryptionScheme`, tells NIP-04 from NIP-44.

NIP-77 is in [`dostr_nip77`](https://pub.dev/packages/dostr_nip77), with `NegentropyEncoder` and `Nip77Result`.
`GlobalState` no longer has `inFlightNegotiations`, `RelayManager` no longer has `onNegMsg`, `onNegErr` or `onNegClosed`.
A protocol of its own, NIP-77 included, plugs in with a `RelayProtocolHandler` and `addProtocolHandler`, from `package:dostr_core/protocol.dart`, which also has `send` and `accountForAuth`.

`Tuple`, `Helpers` and `MutexSimple` are gone: use `DateTime.now().millisecondsSinceEpoch ~/ 1000` for `Helpers.now`.
`castToListOfListOfString` of `package:ndk/shared/helpers/list_casting.dart` is gone.

`dostr_core` makes no HTTP calls and does not read NIP-11 documents.
`RelayInfo` is in [`dostr_nip11`](https://pub.dev/packages/dostr_nip11), `RelayInfoRepo` is its `RelayInfoRepository`, and `RelayInfoHttpRepoImpl(httpDS: http)` is its `HttpRelayInfoRepository(client)`, which takes an `http.Client`.
`HttpRequestDS` is gone: the packages that make HTTP calls take an `http.Client`.
The deprecated `RelayInfo.get` is gone.

`configureDefaultUserAgent` of `package:ndk/shared/net/user_agent.dart` is gone: set `WebSocket.userAgent` of `dart:io`, which is all it did.
`packageVersion` is gone too.

`Nip13` is in [`dostr_nip13`](https://pub.dev/packages/dostr_nip13).
`Nip01Utils` is gone: `Nip01Event` computes its own id, `hasValidId` checks it and `payloadId` recomputes it from the payload.
`hasValidId` checks the id alone, where `Nip01Utils.isIdValid` also rejected an event that misses the proof-of-work target its `nonce` tag declares.

## Defaults

`RelayManager` no longer takes `bootstrapRelays` and no longer has `seedRelaysConnected`: it opens no connection when it is built.
`dostr_core` has no `DEFAULT_BOOTSTRAP_RELAYS`.
Nothing replaces `ndk.relays.seedRelaysConnected`.
`RequestDefaults` and `BroadcastDefaults` are gone.
The defaults of the parameters of `dostr_core` are top-level constants, and the rest is gone: `DEFAULT_USER_AGENT` and `MAX_INBOX_RELAYS_TO_BROADCAST`, among others.
`FAIL_RELAY_CONNECT_TRY_AFTER_SECONDS` and the other constants that tune the reconnection and the relay limits are internal.

`connectTimeout`, on `RelayManager.connectRelay` and `RelayManager.openConnectionAs`, is a `Duration` instead of a number of seconds, and so is `defaultWebSocketConnectTimeout`.

The default constants are in lowerCamelCase: `DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT` is `defaultWebSocketConnectTimeout`, `RequestDefaults.DEFAULT_AUTH_CALLBACK_TIMEOUT` is `defaultAuthCallbackTimeout`, `RequestDefaults.DEFAULT_QUERY_TIMEOUT` is `defaultQueryTimeout` and `BroadcastDefaults.TIMEOUT` is `defaultPublishTimeout`.
`RX_REPLAYSUBJECT_MAX_EVENTS`, which nothing read, is gone.

## `RelayManager`

`RelayManager` and `RelayConnectivity` are no longer generic.
`RelayManager` is a final class, and so are `RelayReqs`, `RelayReq`, `RelayPublishes` and `RelayPublish`: they can no longer be extended, implemented or mocked.
`EngineAdditionalDataFactory` and `RelayConnectivity.specificEngineData` are gone: they only served the JIT engine of `ndk`.

`GlobalState` and `RequestState` are no longer public: `RelayManager` keeps its own state and no longer takes a `globalState`.
Read its connections with `RelayManager.connectivities`.
Nothing lists the REQs and publishes in flight: keep the `RelayReq` or `RelayPublish` you opened, whose `done` completes once it is over.
`RelayManager.blockRelay` blocks a relay and closes its connections, `unblockRelay` lets it be connected to again, and `blockedRelays` lists the blocked relays without letting them be changed.

`RelayManager` keeps the plumbing behind `RelayReq` and publishes to itself.
`sendOrThrow`, `registerRelayRequest`, `registerRelayBroadcast`, `failBroadcast`, `failRelayRequest`, `connectionForBroadcast`, `isStillInFlight`, `beginPendingConnection`, `endPendingConnection`, `sendCloseToRelay`, `sendCloseToConnection`, `reSubscribeInFlightSubscriptions`, `updateRelayConnectivity` and the deprecated `authenticateIfNeeded` are gone, and so is `RequestState.registerRequest`.
Send any message other than a REQ or an EVENT with `send`, from `package:dostr_core/protocol.dart`, which now takes the `RelayConnectionKey` of a connection and the message as a JSON array, such as `['NEG-CLOSE', subscriptionId]`, instead of a `RelayConnectivity` and a `ClientMsg`.
`RelayManager.reconnectClosedConnections` reconnects and replays the requests that `reSubscribeInFlightSubscriptions` used to replay by hand.

`RelayManager.connectRelay` returns a `({bool connected, RelayFailure? failure})` record, with a null `failure` once connected.
It no longer takes an `authPubkey` and only opens the anonymous connection: open one bound to an identity with `RelayManager.openConnectionAs`, which asks the `AuthHandler` first.

`isRelayConnecting`, `isConnectionConnecting`, `reconnectRelays`, `reconnectRelay`, `reconnectConnection`, `resetTransport`, the `resetConnection` of a single connection and `waitForRequestSent` are gone.
Open a connection with `connectRelay` or `openConnectionAs`, and close one with `closeConnection` or `closeConnectionsTo`.
`connectedRelays`, `connectedAnonymousRelays`, `isRelayConnected`, `isConnectionOpen`, `getRelayConnectivity` and `getConnectivity` are gone too: read `RelayManager.connectivities`, keyed by `RelayConnectionKey`.
A connection that is still connecting has `isConnecting` set in `RelayManager.connectivities`.
`relayConnectivityChanges` emits when a connection is added, starts connecting, opens, closes or is forgotten, and no longer each time a REQ is sent or ends.
`allowReconnect`, `authCallbackTimeout`, `authChallengeTimeout`, `authHandler` and `nostrTransportFactory` are constructor parameters only, no longer fields, and `allowReconnectRelays` is gone.

`RelayConnectivity` is a snapshot: `connectivities`, `relayConnectivityChanges` and `openConnectionAs` give each connection as it stood when they were read, and nothing changes it afterwards.
It used to give the live connection, so a list kept from `relayConnectivityChanges` changed under its holder.
It no longer has a public constructor.
`RelayConnectivity` no longer has `url`, `relayTransport`, `listen` or `close`: read `key.url` and `isConnected`, and close a connection with `RelayManager.closeConnection`.
`Relay` and `RelayStats` are gone, and so are `RelayConnectivity.relay` and `stats`: `RelayConnectivity.isConnecting` replaces `relay.connecting`, and nothing replaces the times and counts they kept.
`RelayConnectionKey.canonical` and `anonymousMarker` are gone: `toString` gives the same text.

A relay message that misses a field or carries one of the wrong type, and a binary frame, are logged and dropped, and so is an exception a `RelayProtocolHandler` throws.
They used to escape as uncaught errors, which end a plain Dart process.

`RelayManager.closeTransport` is now `closeConnectionsTo`: it acts on every connection to the relay, anonymous or bound.
`closeAllTransports` is now `closeAllConnections`, after which the manager connects again for the next request.
`RelayManager.dispose` ends every REQ and publish still in flight, closes the connections and `relayConnectivityChanges`, and leaves the manager unusable: opening a connection, a REQ or a publish on it afterwards throws a `StateError`.

## Relay urls

The relay urls `dostr_core` takes and gives are `RelayUrl`s, from [`dostr_relay_url`](https://pub.dev/packages/dostr_relay_url): normalized urls, as an extension type on `String`, so code that reads one as a `String` keeps working.
Make one with `RelayUrl.parse`, which throws a `FormatException` for a url that is not a relay's, or with `RelayUrl.tryParse`, which returns null.

 - `RelayManager.connectRelay`, `closeConnectionsTo` and `openConnectionAs` take a `RelayUrl`, `connectRelay` as its first argument instead of a `dirtyUrl`.
 - `RelayManager.blockRelay`, `unblockRelay` and `blockedRelays` take and give `RelayUrl`s, so a relay blocked in another spelling is blocked too.
 - `RelayConnectionKey.anonymous`, `RelayConnectionKey.authenticated` and `RelayConnectionKey.forAuth` take a `RelayUrl` and no longer normalize it.
 - `RelayPublishes.publish` and the `relays` of `RelayReqs.req` take `RelayUrl`s.
 - `RelayConnectionKey.url` and `RelayReqEvent.relayUrl` are `RelayUrl`s, and so are the keys of `RelayReq.outcomes` and `RelayPublish.outcomes`.
 - `NostrTransportFactory`, `SubscriptionLimit`, `MessageLengthLimit` and `onMessageLengthLearned` are given a `RelayUrl`. One written for a `String` still fits.
 - The factory `webSocketTransportFactory` returns no longer throws on a url it cannot parse, since it is given a `RelayUrl`.

## Transports

`RelayManager` is the only thing that reconnects, and a `NostrTransport` is a single socket.
`NostrTransport` is an interface class: a transport implements it and inherits nothing.
`isOpen`, `closeCode` and `closeReason` are getters, and `isConnecting`, which `RelayManager` never read, is gone.
`ready` completes once the socket is open and fails when it cannot connect or is closed first, instead of waiting forever.
The end of `listen` means the socket is gone.

`NostrTransportFactory` is a function type, `NostrTransport Function(RelayUrl url)`, like `SubscriptionLimit` and `MessageLengthLimit`: it takes the url alone, without `onReconnect` or `onDisconnect`.
`WebSocketClientNostrTransportFactory(...)` is now `webSocketTransportFactory(...)`, which takes the same `compressionEnabled` and `pingInterval` and returns one.
A factory of your own is a function, or the `call` tear-off of an object that has one.

`WebSocketNostrTransportFactory`, `WebSocketNostrTransport` and `WebsocketDS` are gone: they reported a socket open before its handshake, which skipped the connect timeout and kept `closeIdleConnections` from closing anything.
`WebsocketDSClient` and `WebSocketClientNostrTransport` are gone too: the sockets `webSocketTransportFactory` opens run on `web_socket_channel`, not on a copy of `web_socket_client`.
`reconnectMaximumStep` moved from the WebSocket factory to `RelayManager`, as `reconnectMaximumDelay`: the longest wait between two attempts, a `Duration` instead of a number of doublings.

## Reconnecting

A connection that drops is retried at once, then after a wait that doubles from 500 milliseconds, for an hour by default.
Its requests are replayed once it is back, and given up as `disconnected` after that hour.
`reconnectGiveUpAfter` sets that hour, and null never gives up.
The REQs sent to it meanwhile wait for it the same way, so a query does not end without it.
A publish sent to it meanwhile waits for it as long as the publish lasts.
`allowReconnect` set to false now stops these retries: the transport used to retry on its own regardless.
A connection that drops within a minute of opening comes back too.
One that carries nothing `closeIdleConnections` would keep is forgotten instead, when it drops or before an attempt to bring it back: a relay that closes idle sockets used to get them reopened forever.

A REQ leaves a relay alone for a minute only after an attempt to connect to it failed, where it did after any attempt, one that succeeded too.
`unreachableRelayRetryAfter` sets that minute, and `Duration.zero` tries every time.

## Idle connections

A connection is closed once it went without work, as `closeIdleConnections` counts it, and without any message sent or received, for `anonymousIdleTimeout` (a minute by default) or, when it is bound to an identity, `authenticatedIdleTimeout` (five minutes by default).
Connections used to stay open until they were closed explicitly.
Null keeps them open.

A publish keeps open only the connection it goes out on, where it kept every connection to its relay, the anonymous one and the bound ones.

`reconnectClosedConnections` reconnects every connection at once instead of one after the other.
`authenticateConnection` answers false for a connection that is not open.

## REQs

Open REQs with `RelayReqs`, and close one with `RelayReq.close` or by cancelling its `events`.
`RelayReqs.req` takes its `relays` up front: `RelayReq.send` and `seal` are gone.
`RelayReq.closeOnEose` and `timedOut` are gone: the caller knows the first, and a relay the timeout ended reports `RelayRequestStatus.timedOut` in `outcomes`.
`RelayReqs.clearVerifiedEventCache` is gone: the signatures it checked are kept in a bounded cache.

A query given no `timeout` ends after `defaultQueryTimeout`, 10 seconds, as in `ndk`, so a relay that never sends its EOSE cannot hold it open.
A subscription has no timeout unless it is given one.

`RelayReq.events` gives each event as a `RelayReqEvent`, with the relay that sent it in `relayUrl`.
The deprecated `Nip01Event.sources` is gone.

`RelayReq.events` drops an event that matches none of the filters sent to its relay, its `search` aside.
It hands out the events in the order the relays sent them, where they used to come in the order their signatures were checked.
An event whose `EventVerifier` throws is logged and dropped, where the error used to escape as an uncaught error.

`EventFilter` is gone, since no request takes one any more: filter `RelayReq.events` with `where`.

A subscription now reports `RelayRequestStatus.eose` on each relay that sent its EOSE, instead of staying `pending` until it is closed.
It still runs until closed, and a CLOSED, a lost connection or its timeout replace that `eose`.

Closing a connection, with `closeConnection`, `closeConnectionsTo` or `closeAllConnections`, ends the REQs still on it as `disconnected`, where they used to stay `pending` until their timeout, or for good without one.
A REQ closed with `RelayReq.close`, or by cancelling its `events`, reports `RelayRequestStatus.cancelled` on the relays that had yet to end it, where they stayed `pending`.

## Publishes

`BroadcastState` is no longer public, and `RelayBroadcastResponse` is now `RelayPublishOutcome`, in `package:dostr_core/dostr_core.dart`.
Its `status`, a `RelayPublishStatus`, says what the relay did: `pending`, `accepted`, `refused`, `failed` or `timedOut`.
`broadcastSuccessful` is now the `accepted` getter, `msg` is now `message`, and `okReceived` is gone: a relay answered once its status is `accepted` or `refused`.
Its fields are final and its constructor is private: build one with `RelayPublishOutcome.pending`, `accepted`, `refused`, `failed` or `timedOut`, so that no outcome is answered and failed at once.
It no longer has `relayUrl`, since the outcomes are keyed by relay url, and two outcomes are equal when all their fields are, where two responses were equal when they came from the same relay.
Publish a signed event with `RelayPublishes.publish`.

A `RelayPublish` reports like a `RelayReq`: `outcomes`, `outcomesStream` and `done` give the `RelayPublishOutcome` of each relay, keyed by relay url.

`considerDonePercent` and `BroadcastDefaults.CONSIDER_DONE_PERCENT` are gone: a publish is done once every relay answered, or after its `timeout`.
A relay that has not answered by then is `timedOut`, where it stayed without an answer.
The first answer of a relay stands: a failure that comes after its OK no longer replaces it.
Ending a publish early also stopped sending the event again to the relays that had not answered, after an `auth-required` or a dropped connection.
To move on once enough relays accepted the event, wait on `outcomesStream`: the publish goes on for the others.

What `dostr_core` itself failed at comes as a `RelayFailure`, whose `RelayFailureKind` says what it was and whose `detail` may say more, instead of a sentence of its own in a message.
`RelayRequestOutcome.failure` holds it for `notSent`, `RelayPublishOutcome.failure` for a relay the event did not reach, and `connectRelay` returns it.
An EVENT whose socket drops before the relay's OK is sent again once the connection is back.
The relay fails with `RelayFailureKind.connectionLost` once nothing will bring the connection back, when it is closed, blocked, given up, or drops while `allowReconnect` is false, where it used to stay without an answer until the timeout.

`RelayRequestOutcome.message` and `RelayPublishOutcome.message` only hold what the relay sent in its CLOSED or OK, and a publish the relay refused for want of an identity it may not reveal reports `RelayFailureKind.identityNotAllowed`, with the relay's message as its `detail`.

## Filters (`dostr_nip01`)

An empty list in a `Filter` matches nothing, as NIP-01 requires, instead of standing for an absent one.
`toJson`, `fromJson` and `clone` keep `authors: []`, where they used to drop it and leave a filter with no author constraint at all.
`Filter.matchesNothing` tells whether a filter can match any event, and `Filter.matches` whether an event meets every condition of a filter.

`Filter.toMap` and `Filter.fromMap` are now `toJson` and `fromJson`, as in `Nip01Event`.
`fromJson` is strict: a field of the wrong type throws a `FormatException` instead of a `TypeError`, and `Filter.tryFromJson` returns null where it throws.
`fromJson`, `setTag` and `getTag` take a tag name of any length, where they used to ignore the longer ones.

`Filter.cloneWithAuthors`, `cloneWithPTags` and `mergeAuthors` are gone: use `filter.clone()..authors = authors`, `filter.clone()..setTag('p', pTags)` and `a.clone()..authors = {...a.authors!, ...b.authors!}.toList()`.

`Filter.tTags` and `mTags` are gone, from the constructor too: use `getTag('t')` and `tags: {'t': hashtags}`.

`Filter.clone` copies the values of the tag filters too, which it used to share with the original filter.

`RelayReqs.req` leaves out the filters that match nothing, and does not send to a relay left with none.
A REQ whose filters all match nothing ends right away, with no relay in its outcomes.
An empty tag list no longer means "has this tag".

## Events (`dostr_nip01`)

A `created_at` of 0 is kept.
`Nip01Event` used to read it as "now", which rewrote the `created_at` of an event received with 0 and made its id invalid.
Leave `createdAt` out to get the current time.

`Nip01Event.getTags` and `pTags` return the values as the event holds them, where they used to trim and lowercase them.

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
`toBase64()` is gone: use `base64Encode(utf8.encode(event.toJsonString()))`.

`fromJson` is strict.
It used to read a missing `pubkey` or `content` as `''` and missing `tags` as none, to skip a tag that is not a list and to turn tag values into strings: it now throws a `FormatException` for all of these, and for a missing `created_at` or `kind` instead of a `TypeError`.
A missing `id`, which it read as `''`, is now computed.
`Nip01Event.tryFromJson` returns null where `fromJson` throws.
`toJson` no longer writes `"sig": null` for an unsigned event.

The deprecated members are gone:

| Gone | Use |
| --- | --- |
| `Nip01Utils.isIdValid(event)` | `event.hasValidId` |
| `Nip01Utils.calculateId(event)` | `event.payloadId` |
| `event.getDtag()` | `event.dTag` |
| `event.getEId()` | `event.getFirstTag('e')` |
| `event.tTags` | `event.getTags('t')` |
| `event.replyETags` | the NIP-10 `reply` marker, read from `event.tags` |

`EventVerifier` is now an interface: implement it instead of extending it.
