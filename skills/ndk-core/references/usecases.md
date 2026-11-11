# Usecases Overview

All accessible via `ndk.<accessor>`.

## Stable

| Accessor | Type | Description |
| -------- | ---- | ----------- |
| `ndk.requests` | `Requests` | Low-level relay queries and subscriptions, from `ndk_requests` |
| `ndk.broadcast` | `Broadcast` | Publish events to relays, from `ndk_broadcast`, retried by `ndk_broadcast_queue` |
| `ndk.accounts` | `Accounts` | Identity/account management, from `ndk_accounts` |
| `ndk.bunkers` | `Bunkers` | NIP-46 remote signing, from `ndk_nip46` |
| `ndk.relays` | `RelayManager` | Relay connections and management |
| `ndk.follows` | `Follows` | Contact lists (NIP-02), from `ndk_follows` |
| `ndk.metadata` | `Metadatas` | User profile metadata (NIP-01 kind 0), from `ndk_metadata` |
| `ndk.userRelayLists` | `UserRelayLists` | NIP-65 relay lists, from `ndk_user_relay_lists` |
| `ndk.lists` | `Lists` | NIP-51 generic lists, from `ndk_lists` |
| `ndk.relaySets` | `RelaySets` | Calculate relay sets for outbox model, from `ndk_user_relay_lists` |
| `ndk.nip05` | `Nip05Usecase` | NIP-05 verify and fetch, from `ndk_nip05` |
| `ndk.giftWrap` | `GiftWrap` | NIP-59 gift wrap create/unwrap |
| `ndk.connectivity` | `Connectivity` | Relay connectivity events and NIP-11 relay info (`RelayInfo` from `ndk_nip11`) |

## Experimental

| Accessor | Type | Description |
| -------- | ---- | ----------- |
| `ndk.zaps` | `Zaps` | Zap requests, invoices and receipts, from `ndk_zaps` (pay with `Nwc.zap`, see wallets.md) |
| `ndk.search` | `Search` | NIP-50 relay search, from `ndk_metadata` |
| `ndk.fetchedRanges` | `FetchedRanges` | Track fetched time ranges per relay, from `ndk_requests` |
| `ndk.nip77` | `Nip77` | Negentropy set reconciliation |

## Broadcast

```dart
// Publish a signed event
final event = Nip01Event(
  pubkey: pubkey,
  kind: 1,
  content: 'hello nostr',
  tags: [],
);

final response = await ndk.broadcast.broadcastEvent(
  event,
  signer: mySigner,
);

await for (final result in response.stream) {
  print('${result.relay}: ${result.ok}');
}
```

## Metadata

`Metadatas` and `Metadata` live in the `ndk_metadata` package (pure Dart, no `ndk` dependency), which `ndk` re-exports.

```dart
final metadata = await ndk.metadata.loadMetadata(pubkey);
print(metadata?.name);
print(metadata?.picture);
print(metadata?.nip05);
```

## Follows

`Follows` and `ContactList` live in the `ndk_follows` package (pure Dart, no `ndk` dependency), which `ndk` re-exports.

```dart
final contactList = await ndk.follows.getContactList(pubkey);
contactList?.contacts; // List<String>, the followed pubkeys
```

## DMs (NIP-17)

Lives in the `ndk_nip17` package, which does not depend on `ndk`: `Dms` sends and loads NIP-17 gift-wrapped messages and publishes the DM relay list (kind 10050). It is built from the parts of the NDK instance it uses.

```dart
import 'package:ndk_nip17/ndk_nip17.dart';

final dms = Dms(
  accounts: ndk.accounts,
  giftWrap: ndk.giftWrap,
  eventVerifier: ndk.config.eventVerifier,
  getDmRelays: ndk.userRelayLists.getDmRelays,
  query:
      (
        filter, {
        required relays,
        required auth,
        required cacheRead,
        required timeout,
      }) => ndk.requests
          .query(
            filter: filter,
            explicitRelays: relays,
            auth: auth,
            cacheRead: cacheRead,
            timeout: timeout,
          )
          .future,
  publish: (event, {relays}) => ndk.broadcast
      .broadcast(nostrEvent: event, specificRelays: relays)
      .broadcastDoneFuture,
  loadCachedGiftWraps: (pubKey) => ndk.config.cache.loadEvents(
    kinds: [GiftWrap.kGiftWrapEventkind],
    tags: {
      'p': [pubKey],
    },
  ),
);

await dms.sendMessage(recipientPubKey: pubkey, content: 'hello');
final conversations = await dms.loadConversations();
```

## Trusted assertions (NIP-85)

Lives in the `ndk_nip85` package and does not depend on `ndk`: `TrustedAssertions` fetches and streams the metrics trusted providers publish (kinds 30382 to 30385). It uses `DEFAULT_NIP85_PROVIDERS` unless given `defaultProviders` or per-call `providers`.

```dart
import 'package:ndk_nip85/ndk_nip85.dart';

final ta = TrustedAssertions(
  query: (filter, {required relay}) =>
      ndk.requests.query(filter: filter, explicitRelays: [relay]).future,
  subscribe: (filter, {required relay}) {
    final response = ndk.requests.subscription(
      filter: filter,
      explicitRelays: [relay],
    );
    return (
      events: response.stream,
      close: () => ndk.requests.closeSubscription(response.requestId),
    );
  },
);

final user = await ta.getUserMetrics(pubkey, metrics: {Nip85Metric.rank});
user?.rank;
```

## Proof of work (NIP-13)

Lives in the `ndk_nip13` package and does not depend on `ndk`: static methods on `Nip13`. `mineEvent` runs in the `ndk_isolates` compute pool and returns an unsigned event with a `nonce` tag, so broadcast it after mining.

```dart
import 'package:ndk_nip13/ndk_nip13.dart';

final mined = await Nip13.mineEvent(event, 20);
Nip13.getDifficulty(mined.id); // >= 20
Nip13.validateEvent(mined); // meets its nonce target
await ndk.broadcast.broadcast(nostrEvent: mined);
```

## Software updates (NIP-82)

Lives in the `ndk_nip82` package and does not depend on `ndk`: `Software` discovers a trusted publisher's application (kind 32267), releases (kind 30063) and assets (kind 3063), and `selectUpdate` picks a compatible Android APK. `ndk_flutter` re-exports it and builds `NAppUpdateController` on it.

```dart
import 'package:ndk_nip82/ndk_nip82.dart';

final software = Software(
  query: (filter, {relays, timeout}) async {
    final response = ndk.requests.query(
      filter: filter,
      explicitRelays: relays,
      timeout: timeout,
    );
    final events = await response.future;
    return (
      events: events,
      anyRelayCompleted: response.relayOutcomes.values.any(
        (outcome) => outcome.status == RelayRequestStatus.eose,
      ),
    );
  },
  subscribe: (filter, {relays}) {
    final response = ndk.requests.subscription(
      filter: filter,
      explicitRelays: relays,
    );
    return (
      events: response.stream,
      close: () => ndk.requests.closeSubscription(response.requestId),
    );
  },
);

final app = SoftwareAppRef(publisher: publisherPubkey, identifier: 'com.example.app');
final releases = await software.getReleases(app: app, relays: catalogRelays);
final assets = await software.resolveAssetsForReleases(releases, relays: catalogRelays);
```

## Files (Blossom)

Lives in the `ndk_blossom` package: `Files(ndk)` (high level), `Blossom(ndk)` (low level) and `BlossomUserServerList(ndk)` (kind 10063).

```dart
import 'package:ndk_blossom/ndk_blossom.dart';

final files = Files(ndk);

// Upload to the logged-in user's server list
final results = await files.upload(
  file: NdkFile(data: bytes, mimeType: 'image/png'),
);

// Download
final blob = await files.download(url: url);
```
