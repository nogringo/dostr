# Coming from `ndk`

Dostr started as the `ndk` package, now split into the packages listed in the [README](../README.md#monorepo-packages).
This page is for code that used `ndk`: where each part moved, and what changed on the way.
Each section lists what was renamed, then what is gone and what to use instead, then what behaves differently.

## Packages and imports

| What | Package | Replaces, under `package:ndk/` |
| --- | --- | --- |
| `RelayManager`, REQs, publishes, transports and their defaults | [`dostr_core`](https://pub.dev/packages/dostr_core) | every deep import of the relay code, such as `domain_layer/entities/relay.dart` or `config/request_defaults.dart` |
| `Nip01Event`, `EventVerifier`, `Filter`, `EventKindClassification` | [`dostr_nip01`](https://pub.dev/packages/dostr_nip01) | `domain_layer/entities/nip_01_event.dart`, `domain_layer/repositories/event_verifier.dart`, `domain_layer/entities/filter.dart`, `shared/nips/nip01/event_kind_classification.dart` |
| `NostrSigner`, `PendingSignerRequest`, the signer exceptions, `AuthPolicy`, `AuthHandler`, `AuthAccounts` | [`dostr_signer`](https://pub.dev/packages/dostr_signer) | `domain_layer/repositories/event_signer.dart`, `domain_layer/entities/pending_signer_request.dart`, `domain_layer/entities/signer_request_rejected_exception.dart`, `domain_layer/entities/signer_request_cancelled_exception.dart`, `domain_layer/entities/auth_policy.dart`, `domain_layer/entities/auth_handler.dart` |
| `RelayUrl`, the relay url normalization | [`dostr_relay_url`](https://pub.dev/packages/dostr_relay_url) | `shared/helpers/relay_helper.dart` |
| `Bip340`, `Bip340EventVerifier`, `KeyPair`, `Bip340Signer`, `Bip340SignerFactory` | [`dostr_bip340`](https://pub.dev/packages/dostr_bip340) | |
| `Nip04`, `Nip44` | [`dostr_nip44`](https://pub.dev/packages/dostr_nip44) | |
| NIP-77, `NegentropyEncoder`, `Nip77Result` | [`dostr_nip77`](https://pub.dev/packages/dostr_nip77) | |
| `RelayInfo` (NIP-11) | [`dostr_nip11`](https://pub.dev/packages/dostr_nip11) | |
| `Nip13` | [`dostr_nip13`](https://pub.dev/packages/dostr_nip13) | |

`package:dostr_core/dostr_core.dart` exports `dostr_nip01`, `dostr_signer` and `dostr_relay_url`, so it covers the first four rows.
Every file of `dostr_core` is under `lib/src` and can no longer be imported on its own.
`NostrMessageRaw`, `decodeNostrMsg`, `ClientMsg`, `verifyEvent` and `VerifiedEventMemCache` are no longer public.

## Logging

| Gone | Instead |
| --- | --- |
| The logger of `ndk`, `package:ndk/shared/logger/*.dart`, `package:ndk/config/logger_defaults.dart` | [`logging`](https://pub.dev/packages/logging) |
| `Logger.setLogLevel(level)` | `Logger.root.level = level`, with the levels of `logging` |

 - `dostr_core` logs under the name `dostr_core`, and prints nothing until the app listens to `Logger.root.onRecord`.
 - A relay that cannot be reached, a socket error, an OK false, a CLOSED and a NOTICE are no longer logged as errors: they are part of talking to relays, and the outcomes report them.
 - `severe` is left to a bug of `dostr_core` or of the app, and `warning` to a relay that misbehaves or a callback of the app that throws.

## Signers

| `ndk` | Dostr |
| --- | --- |
| `EventSigner` | `NostrSigner`, since a signer also encrypts and decrypts |
| `LocalEventSignerFactory` | `LocalSignerFactory` |
| `Bip340EventSigner` | `Bip340Signer` |
| `Bip340EventSignerFactory` | `Bip340SignerFactory` |
| `Bip340.generatePrivateKey` | `Bip340.generateKeyPair` |
| `Nip01Utils.signWithPrivateKey` | `Bip340.signEvent` |
| `getPublicKey()` | the `publicKey` getter |
| `canSign()` | the `canSign` getter |
| `encrypt`, `decrypt` | `encryptNip04`, `decryptNip04`, with the named parameters of the NIP-44 methods |
| `recipientPubKey`, `senderPubKey` of `encryptNip44` and `decryptNip44` | `recipientPubkey`, `senderPubkey` |

| Gone | Instead |
| --- | --- |
| `requiresInteractiveSigning`, `requiresSignerNetwork`, `signerTransportRelayUrls` | nothing |
| `LocalSignerFactory.derivePublicKey` | `create(privateKey).publicKey` |
| `SignerMethod` | the `scheme` of an encryption or a decryption, an `EncryptionScheme`, tells NIP-04 from NIP-44 |

 - `encryptNip04`, `decryptNip04`, `encryptNip44` and `decryptNip44` return a `Future<String>` instead of a `Future<String?>`: a signer that cannot encrypt or decrypt throws.
 - `NostrSigner` and `LocalSignerFactory` are interface classes: a signer implements them and inherits nothing.
 - `LocalSignerFactory.create` takes the private key alone, and `readOnly` takes a public key.
 - `Bip340Signer(privateKey)` derives the public key, and `Bip340Signer.readOnly(publicKey)` replaces a signer without a private key.
 - `Bip340.sign` and `Bip340.verify` take named parameters.
 - `SignerRequestRejectedException`, `SignerRequestCancelledException` and the new `SignerRequestFailedException` are all a `SignerRequestException`.
 - `NostrSigner` says what a signer throws, and that `publicKey` never throws: the [`dostr_signer` changelog](https://pub.dev/packages/dostr_signer/changelog) has the details.
 - `PendingSignerRequest` is a sealed class, a `PendingSignRequest`, `PendingEncryptRequest` or `PendingDecryptRequest`.

## Authentication (NIP-42)

A REQ, a publish or a negentropy sync without `auth` no longer authenticates, even where the `AuthHandler` agrees: `dostr_core` never picks an identity on its own.
It used to authenticate as the logged account, and a publish as the author of its event when that author was an account.
Name the identity instead, such as `auth: AuthPolicy.allow(accounts.getLoggedAccount()!)`.
`authHandler: (_, _) async => true` no longer brings that behavior back.

| `ndk` | Dostr |
| --- | --- |
| `AuthPolicy.account` | `AuthPolicy.signer` |
| the `accounts` map of `AuthAccounts` | `AuthAccounts.getAccount(pubkey)` |
| `TimeoutPausable`, in `auth_handler.dart` | `TimeoutPausable`, in `package:dostr_core/dostr_core.dart` |

| Gone | Instead |
| --- | --- |
| `Account`, from `package:ndk/domain_layer/entities/account.dart` | the account's `NostrSigner` |
| the `authPubkey` of `RelayManager.connectRelay` | `RelayManager.openConnectionAs`, which asks the `AuthHandler` first |
| `AuthPolicy.canonical`, `==`, `hashCode` | nothing |
| `domain_layer/usecases/nip42/auth_event.dart` | nothing: `RelayManager` builds the AUTH event itself |

 - `AuthPolicy.allow` and `AuthPolicy.require` take the signer, and `AuthAccounts` gives signers.
 - `RelayManager.openConnectionAs` and `accountForAuth` take or return a `NostrSigner`.
 - `RelayManager.connectRelay` only opens the anonymous connection.
 - `authenticateConnection` answers false for a connection that is not open.

## Relay urls

The relay urls `dostr_core` takes and gives are `RelayUrl`s: normalized urls, as an extension type on `String`, so code that reads one as a `String` keeps working.
Make one with `RelayUrl.parse`, which throws a `FormatException` for a url that is not a relay's, or with `RelayUrl.tryParse`, which returns null.

| Gone | Instead |
| --- | --- |
| `cleanRelayUrl(url)` | `RelayUrl.tryParse(url)` |
| `cleanRelayUrls(urls)` | `urls.map(RelayUrl.tryParse).nonNulls` |
| `relayUrlRegex` and the url normalizer behind it | `RelayUrl.tryParse`, which builds on `Uri.parse` |

 - `RelayManager.connectRelay`, `closeConnectionsTo` and `openConnectionAs` take a `RelayUrl`, `connectRelay` as its first argument instead of a `dirtyUrl`.
 - `RelayManager.blockRelay`, `unblockRelay` and `blockedRelays` take and give `RelayUrl`s, so a relay blocked in another spelling is blocked too.
 - `RelayConnectionKey.anonymous`, `RelayConnectionKey.authenticated` and `RelayConnectionKey.forAuth` take a `RelayUrl` and no longer normalize it.
 - `RelayPublishes.publish` and the `relays` of `RelayReqs.req` take `RelayUrl`s.
 - `RelayConnectionKey.url` and `RelayReqEvent.relayUrl` are `RelayUrl`s, and so are the keys of `RelayReq.outcomes` and `RelayPublish.outcomes`.
 - `NostrTransportFactory`, `SubscriptionLimit`, `MessageLengthLimit` and `onMessageLengthLearned` are given a `RelayUrl`. One written for a `String` still fits.
 - The factory `webSocketTransportFactory` returns no longer throws on a url it cannot parse, since it is given a `RelayUrl`.

## Defaults

The defaults of the parameters of `dostr_core` are top-level constants in lowerCamelCase.

| `ndk` | Dostr |
| --- | --- |
| `DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT` | `defaultWebSocketConnectTimeout`, a `Duration` |
| `RequestDefaults.DEFAULT_AUTH_CALLBACK_TIMEOUT` | `defaultAuthCallbackTimeout` |
| `RequestDefaults.DEFAULT_QUERY_TIMEOUT` | `defaultQueryTimeout` |
| `BroadcastDefaults.TIMEOUT` | `defaultPublishTimeout` |
| `connectTimeout` of `RelayManager.connectRelay` and `RelayManager.openConnectionAs`, in seconds | `connectTimeout`, a `Duration` |

| Gone | Instead |
| --- | --- |
| `bootstrapRelays` of `RelayManager`, `DEFAULT_BOOTSTRAP_RELAYS` | nothing: `RelayManager` opens no connection when it is built |
| `RelayManager.seedRelaysConnected`, `ndk.relays.seedRelaysConnected` | nothing |
| `RequestDefaults`, `BroadcastDefaults` | the top-level constants above |
| `DEFAULT_USER_AGENT`, `MAX_INBOX_RELAYS_TO_BROADCAST`, among others | nothing |
| `FAIL_RELAY_CONNECT_TRY_AFTER_SECONDS` and the other constants that tune the reconnection and the relay limits | nothing: they are internal |
| `RX_REPLAYSUBJECT_MAX_EVENTS` | nothing: nothing read it |

## Connections (`RelayManager`)

| `ndk` | Dostr |
| --- | --- |
| `RelayManager.closeTransport` | `closeConnectionsTo`, which acts on every connection to the relay, anonymous or bound |
| `RelayManager.closeAllTransports` | `closeAllConnections`, after which the manager connects again for the next request |
| `RelayConnectivity.url` | `RelayConnectivity.key.url` |
| `RelayConnectivity.relay.connecting` | `RelayConnectivity.isConnecting` |
| `RelayConnectionKey.canonical`, `anonymousMarker` | `RelayConnectionKey.toString`, which gives the same text |

| Gone | Instead |
| --- | --- |
| `GlobalState`, `RequestState`, the `globalState` of `RelayManager` | nothing: `RelayManager` keeps its own state, and `RelayManager.connectivities` gives its connections |
| a list of the REQs and publishes in flight | keep the `RelayReq` or `RelayPublish` you opened, whose `done` completes once it is over |
| `connectedRelays`, `connectedAnonymousRelays`, `isRelayConnected`, `isConnectionOpen`, `getRelayConnectivity`, `getConnectivity` | `RelayManager.connectivities`, keyed by `RelayConnectionKey` |
| `isRelayConnecting`, `isConnectionConnecting` | `isConnecting`, in `RelayManager.connectivities` |
| `reconnectRelays`, `reconnectRelay`, `reconnectConnection`, `resetTransport`, the `resetConnection` of a single connection, `waitForRequestSent` | `connectRelay` or `openConnectionAs` to open a connection, `closeConnection` or `closeConnectionsTo` to close one |
| `reSubscribeInFlightSubscriptions` | `RelayManager.reconnectClosedConnections`, which reconnects and replays the requests |
| `sendOrThrow`, `registerRelayRequest`, `registerRelayBroadcast`, `failBroadcast`, `failRelayRequest`, `connectionForBroadcast`, `isStillInFlight`, `beginPendingConnection`, `endPendingConnection`, `sendCloseToRelay`, `sendCloseToConnection`, `updateRelayConnectivity`, the deprecated `authenticateIfNeeded`, `RequestState.registerRequest` | nothing: `RelayManager` keeps the plumbing behind `RelayReq` and publishes to itself |
| `send` with a `RelayConnectivity` and a `ClientMsg` | `send`, from `package:dostr_core/protocol.dart`, with the `RelayConnectionKey` of a connection and the message as a JSON array, such as `['NEG-CLOSE', subscriptionId]` |
| `allowReconnect`, `authCallbackTimeout`, `authChallengeTimeout`, `authHandler`, `nostrTransportFactory` as fields | the constructor parameters of the same names |
| `allowReconnectRelays` | nothing |
| `RelayConnectivity.relayTransport`, `listen`, `close` | `RelayConnectivity.isConnected`, and `RelayManager.closeConnection` to close a connection |
| `Relay`, `RelayStats`, `RelayConnectivity.relay`, `RelayConnectivity.stats` | nothing keeps the times and counts they kept |
| `EngineAdditionalDataFactory`, `RelayConnectivity.specificEngineData` | nothing: they only served the JIT engine of `ndk` |
| the public constructor of `RelayConnectivity` | nothing |

 - `RelayManager` and `RelayConnectivity` are no longer generic.
 - `RelayManager`, `RelayReqs`, `RelayReq`, `RelayPublishes` and `RelayPublish` are final classes: they can no longer be extended, implemented or mocked.
 - `RelayManager.blockRelay` blocks a relay and closes its connections, `unblockRelay` lets it be connected to again, and `blockedRelays` lists the blocked relays without letting them be changed.
 - `RelayManager.connectRelay` returns a `({bool connected, RelayFailure? failure})` record, with a null `failure` once connected.
 - `relayConnectivityChanges` emits when a connection is added, starts connecting, opens, closes or is forgotten, and no longer each time a REQ is sent or ends.
 - `RelayConnectivity` is a snapshot: `connectivities`, `relayConnectivityChanges` and `openConnectionAs` give each connection as it stood when they were read, and nothing changes it afterwards. It used to give the live connection, so a list kept from `relayConnectivityChanges` changed under its holder.
 - A relay message that misses a field or carries one of the wrong type, and a binary frame, are logged and dropped, and so is an exception a `RelayProtocolHandler` throws. They used to escape as uncaught errors, which end a plain Dart process.
 - `RelayManager.dispose` ends every REQ and publish still in flight, closes the connections and `relayConnectivityChanges`, and leaves the manager unusable: opening a connection, a REQ or a publish on it afterwards throws a `StateError`.

## Transports

`RelayManager` is the only thing that reconnects, and a `NostrTransport` is a single socket.

| `ndk` | Dostr |
| --- | --- |
| `WebSocketClientNostrTransportFactory(...)` | `webSocketTransportFactory(...)`, which takes the same `compressionEnabled` and `pingInterval` and returns a factory |
| `reconnectMaximumStep` of the WebSocket factory, a number of doublings | `reconnectMaximumDelay` of `RelayManager`, the longest wait between two attempts, as a `Duration` |

| Gone | Instead |
| --- | --- |
| `WebSocketNostrTransportFactory`, `WebSocketNostrTransport`, `WebsocketDS` | `webSocketTransportFactory`: they reported a socket open before its handshake, which skipped the connect timeout and kept `closeIdleConnections` from closing anything |
| `WebsocketDSClient`, `WebSocketClientNostrTransport` | `webSocketTransportFactory`, whose sockets run on `web_socket_channel`, not on a copy of `web_socket_client` |
| the `onReconnect` and `onDisconnect` of a transport factory | nothing: a factory takes the url alone |
| `NostrTransport.isConnecting` | nothing: `RelayManager` never read it |

 - `NostrTransportFactory` is a function type, `NostrTransport Function(RelayUrl url)`, like `SubscriptionLimit` and `MessageLengthLimit`. A factory of your own is a function, or the `call` tear-off of an object that has one.
 - `NostrTransport` is an interface class: a transport implements it and inherits nothing.
 - `isOpen`, `closeCode` and `closeReason` are getters.
 - `ready` completes once the socket is open and fails when it cannot connect or is closed first, instead of waiting forever.
 - The end of `listen` means the socket is gone.

## Reconnecting and idle connections

 - A connection that drops is retried at once, then after a wait that doubles from 500 milliseconds, for an hour by default.
 - Its requests are replayed once it is back, and given up as `disconnected` after that hour. `reconnectGiveUpAfter` sets that hour, and null never gives up.
 - The REQs sent to it meanwhile wait for it the same way, so a query does not end without it. A publish sent to it meanwhile waits for it as long as the publish lasts.
 - `allowReconnect` set to false now stops these retries: the transport used to retry on its own regardless.
 - A connection that drops within a minute of opening comes back too.
 - A connection that carries nothing `closeIdleConnections` would keep is forgotten instead, when it drops or before an attempt to bring it back: a relay that closes idle sockets used to get them reopened forever.
 - A REQ leaves a relay alone for a minute only after an attempt to connect to it failed, where it did after any attempt, one that succeeded too. `unreachableRelayRetryAfter` sets that minute, and `Duration.zero` tries every time.
 - A connection is closed once it went without work, as `closeIdleConnections` counts it, and without any message sent or received, for `anonymousIdleTimeout` (a minute by default) or, when it is bound to an identity, `authenticatedIdleTimeout` (five minutes by default). Connections used to stay open until they were closed explicitly. Null keeps them open.
 - A publish keeps open only the connection it goes out on, where it kept every connection to its relay, the anonymous one and the bound ones.
 - `reconnectClosedConnections` reconnects every connection at once instead of one after the other.
 - `suspend` and `resume` are new: call them when the app goes to the background and comes back, see the README of `dostr_core`.

## REQs

Open REQs with `RelayReqs`, and close one with `RelayReq.close` or by cancelling its `events`.

| Gone | Instead |
| --- | --- |
| `RelayReq.send`, `seal` | the `relays` of `RelayReqs.req`, given up front |
| `RelayReq.closeOnEose` | nothing: the caller knows it |
| `RelayReq.timedOut` | `RelayRequestStatus.timedOut`, in `outcomes`, on each relay the timeout ended |
| `RelayReqs.clearVerifiedEventCache` | nothing: the signatures it checked are kept in a bounded cache |
| `VerifyEventStream` | nothing: `RelayReq.events` verifies its events itself |
| `EventFilter` | `where` on `RelayReq.events`, since no request takes one any more |
| the deprecated `Nip01Event.sources` | `RelayReqEvent.relayUrl` |

 - `RelayReq.events` gives each event as a `RelayReqEvent`, with the relay that sent it in `relayUrl`.
 - A query given no `timeout` ends after `defaultQueryTimeout`, 10 seconds, as in `ndk`, so a relay that never sends its EOSE cannot hold it open. A subscription has no timeout unless it is given one.
 - `RelayReq.events` drops an event that matches none of the filters sent to its relay, its `search` aside.
 - It hands out the events in the order the relays sent them, where they used to come in the order their signatures were checked.
 - An event whose `EventVerifier` throws is logged and dropped, where the error used to escape as an uncaught error.
 - A subscription now reports `RelayRequestStatus.eose` on each relay that sent its EOSE, instead of staying `pending` until it is closed. It still runs until closed, and a CLOSED, a lost connection or its timeout replace that `eose`.
 - Closing a connection, with `closeConnection`, `closeConnectionsTo` or `closeAllConnections`, ends the REQs still on it as `disconnected`, where they used to stay `pending` until their timeout, or for good without one.
 - A REQ closed with `RelayReq.close`, or by cancelling its `events`, reports `RelayRequestStatus.cancelled` on the relays that had yet to end it, where they stayed `pending`.

## Publishes

Publish a signed event with `RelayPublishes.publish`.
A `RelayPublish` reports like a `RelayReq`: `outcomes`, `outcomesStream` and `done` give the `RelayPublishOutcome` of each relay, keyed by relay url.

| `ndk` | Dostr |
| --- | --- |
| `RelayBroadcastResponse` | `RelayPublishOutcome`, in `package:dostr_core/dostr_core.dart` |
| `RelayBroadcastResponse.broadcastSuccessful` | the `RelayPublishOutcome.accepted` getter |
| `RelayBroadcastResponse.msg` | `RelayPublishOutcome.message` |

| Gone | Instead |
| --- | --- |
| `BroadcastState` | nothing: it is no longer public |
| `okReceived` | `status`: a relay answered once it is `accepted` or `refused` |
| `RelayBroadcastResponse.relayUrl` | the relay url the outcome is keyed by |
| `considerDonePercent`, `BroadcastDefaults.CONSIDER_DONE_PERCENT` | wait on `outcomesStream` to move on once enough relays accepted the event: the publish goes on for the others |

 - The `status` of an outcome, a `RelayPublishStatus`, says what the relay did: `pending`, `accepted`, `refused`, `failed` or `timedOut`.
 - Its fields are final and its constructor is private: build one with `RelayPublishOutcome.pending`, `accepted`, `refused`, `failed` or `timedOut`, so that no outcome is answered and failed at once.
 - Two outcomes are equal when all their fields are, where two responses were equal when they came from the same relay.
 - A publish is done once every relay answered, or after its `timeout`. A relay that has not answered by then is `timedOut`, where it stayed without an answer.
 - Ending a publish early, as `considerDonePercent` did, also stopped sending the event again to the relays that had not answered, after an `auth-required` or a dropped connection.
 - The first answer of a relay stands: a failure that comes after its OK no longer replaces it.
 - An EVENT whose socket drops before the relay's OK is sent again once the connection is back.
 - The relay fails with `RelayFailureKind.connectionLost` once nothing will bring the connection back, when it is closed, blocked, given up, or drops while `allowReconnect` is false, where it used to stay without an answer until the timeout.
 - What `dostr_core` itself failed at comes as a `RelayFailure`, whose `RelayFailureKind` says what it was and whose `detail` may say more, instead of a sentence of its own in a message. `RelayRequestOutcome.failure` holds it for `notSent`, `RelayPublishOutcome.failure` for a relay the event did not reach, and `connectRelay` returns it.
 - `RelayRequestOutcome.message` and `RelayPublishOutcome.message` only hold what the relay sent in its CLOSED or OK.
 - A publish the relay refused for want of an identity it may not reveal reports `RelayFailureKind.identityNotAllowed`, with the relay's message as its `detail`.

## Filters (`dostr_nip01`)

| `ndk` | Dostr |
| --- | --- |
| `Filter.toMap` | `Filter.toJson`, as in `Nip01Event` |
| `Filter.fromMap` | `Filter.fromJson` |

| Gone | Instead |
| --- | --- |
| `Filter.cloneWithAuthors` | `filter.clone()..authors = authors` |
| `Filter.cloneWithPTags` | `filter.clone()..setTag('p', pTags)` |
| `Filter.mergeAuthors` | `a.clone()..authors = {...a.authors!, ...b.authors!}.toList()` |
| `Filter.tTags`, `Filter.mTags`, in the constructor too | `getTag('t')` and `tags: {'t': hashtags}`, and the same with `'m'` |

 - An empty list in a `Filter` matches nothing, as NIP-01 requires, instead of standing for an absent one. An empty tag list no longer means "has this tag".
 - `toJson`, `fromJson` and `clone` keep `authors: []`, where they used to drop it and leave a filter with no author constraint at all.
 - `Filter.matchesNothing` tells whether a filter can match any event, and `Filter.matches` whether an event meets every condition of a filter.
 - `RelayReqs.req` leaves out the filters that match nothing, and does not send to a relay left with none. A REQ whose filters all match nothing ends right away, with no relay in its outcomes.
 - `fromJson` is strict: a field of the wrong type throws a `FormatException` instead of a `TypeError`, and `Filter.tryFromJson` returns null where it throws.
 - `fromJson`, `setTag` and `getTag` take a tag name of any length, where they used to ignore the longer ones.
 - `Filter.clone` copies the values of the tag filters too, which it used to share with the original filter.

## Events (`dostr_nip01`)

| `ndk` | Dostr |
| --- | --- |
| `Nip01Event.pubKey` | `Nip01Event.pubkey`, the name NIP-01 gives the field |
| `Nip01Event.kTextNodeKind` | `Nip01Event.kTextNoteKind` |
| `EventKindClassification.isParameterizedReplaceableKind` | `isAddressableKind`, the name NIP-01 now gives these kinds |
| `Nip01Utils.isIdValid(event)` | `event.hasValidId` |
| `Nip01Utils.calculateId(event)` | `event.payloadId` |
| `event.getDtag()` | `event.dTag` |
| `event.getEId()` | `event.getFirstTag('e')` |
| `event.tTags` | `event.getTags('t')` |

| Gone | Instead |
| --- | --- |
| `Nip01Utils` | `Nip01Event`, which computes its own id: `hasValidId` checks it and `payloadId` recomputes it from the payload |
| `event.replyETags` | the NIP-10 `reply` marker, read from `event.tags` |
| `EventKindClassification.isRegularReplaceableKind`, `legacyReplaceableKinds` | `isReplaceableKind`, which covers them |
| `Nip01Event.validSig`, from `copyWith` and the constructors too | nothing: a request only hands out events whose id and signature it checked, and nothing read the flag |
| `Nip01Event.secondsSinceEpoch()` | leave `createdAt` out to get the current time |
| `Nip01EventModel` | `Nip01Event`, which has its `fromJson`, `toJson` and `toJsonString`, and `event` itself instead of `Nip01EventModel.fromEntity(event)` |
| `toBase64()` | `base64Encode(utf8.encode(event.toJsonString()))` |

 - A `created_at` of 0 is kept. `Nip01Event` used to read it as "now", which rewrote the `created_at` of an event received with 0 and made its id invalid. Leave `createdAt` out to get the current time.
 - `Nip01Event.getTags` and `pTags` return the values as the event holds them, where they used to trim and lowercase them.
 - `Nip01Event.tags` is a copy of the tags the event was created with, and neither it nor any of its tags can be changed: build another event with `copyWith`. Changing the list an event was created from used to change its tags without changing its id.
 - `copyWith` gives a copy whose `pubkey`, `createdAt`, `kind`, `tags` or `content` changed the id of its new payload, and drops a `sig` that no longer matches that id. It used to keep the old id and signature. Pass `id` to keep another one, such as the id a remote signer chose.
 - `hasValidId` checks the id alone, where `Nip01Utils.isIdValid` also rejected an event that misses the proof-of-work target its `nonce` tag declares.
 - `fromJson` is strict. It used to read a missing `pubkey` or `content` as `''` and missing `tags` as none, to skip a tag that is not a list and to turn tag values into strings: it now throws a `FormatException` for all of these, and for a missing `created_at` or `kind` instead of a `TypeError`.
 - A missing `id`, which `fromJson` read as `''`, is now computed.
 - `Nip01Event.tryFromJson` returns null where `fromJson` throws.
 - `toJson` no longer writes `"sig": null` for an unsigned event.
 - `Nip01Event` is a final class: it can no longer be extended, implemented or mocked. Build the events a test needs with its constructor or `fromJson`.
 - `EventKindClassification` only has static members, and can no longer be instantiated or extended.
 - `EventVerifier` is now an interface: implement it instead of extending it.

## NIP-77, NIP-11 and helpers

| `ndk` | Dostr |
| --- | --- |
| `RelayInfoRepo` | `RelayInfoRepository`, in `dostr_nip11` |
| `RelayInfoHttpRepoImpl(httpDS: http)` | `HttpRelayInfoRepository(client)`, which takes an `http.Client` |

| Gone | Instead |
| --- | --- |
| `GlobalState.inFlightNegotiations`, `RelayManager.onNegMsg`, `onNegErr`, `onNegClosed` | [`dostr_nip77`](https://pub.dev/packages/dostr_nip77) |
| `HttpRequestDS` | an `http.Client`, which the packages that make HTTP calls take |
| the deprecated `RelayInfo.get` | `HttpRelayInfoRepository(client).getRelayInfo(url)` |
| `IsolateManager` and its pool | nothing: relay messages are decoded on the main isolate |
| `runInComputeIsolate` | `Isolate.run`, for your own work |
| `configureDefaultUserAgent`, from `package:ndk/shared/net/user_agent.dart` | `WebSocket.userAgent` of `dart:io`, which is all it set |
| `packageVersion` | nothing |
| `Helpers.now` | `DateTime.now().millisecondsSinceEpoch ~/ 1000` |
| `Tuple`, the rest of `Helpers`, `MutexSimple` | nothing |
| `castToListOfListOfString`, from `package:ndk/shared/helpers/list_casting.dart` | nothing |

 - `dostr_core` makes no HTTP calls and does not read NIP-11 documents.
 - A protocol of its own, NIP-77 included, plugs in with a `RelayProtocolHandler` and `addProtocolHandler`, from `package:dostr_core/protocol.dart`, which also has `send` and `accountForAuth`.
