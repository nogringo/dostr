# Usecases Overview

All accessible via `ndk.<accessor>`.

## Stable

| Accessor | Type | Description |
| -------- | ---- | ----------- |
| `ndk.requests` | `Requests` | Low-level relay queries and subscriptions |
| `ndk.broadcast` | `Broadcast` | Publish events to relays |
| `ndk.accounts` | `Accounts` | Identity/account management |
| `ndk.bunkers` | `Bunkers` | NIP-46 remote signing |
| `ndk.relays` | `RelayManager` | Relay connections and management |
| `ndk.follows` | `Follows` | Contact lists (NIP-02) |
| `ndk.metadata` | `Metadatas` | User profile metadata (NIP-01 kind 0) |
| `ndk.userRelayLists` | `UserRelayLists` | NIP-65 relay lists |
| `ndk.lists` | `Lists` | NIP-51 generic lists |
| `ndk.relaySets` | `RelaySets` | Calculate relay sets for outbox model |
| `ndk.nip05` | `Nip05Usecase` | NIP-05 verify and fetch |
| `ndk.giftWrap` | `GiftWrap` | NIP-59 gift wrap create/unwrap |
| `ndk.connectivity` | `Connectivy` | Relay connectivity events |
| `ndk.proofOfWork` | `ProofOfWork` | PoW event generation |

## Experimental

| Accessor | Type | Description |
| -------- | ---- | ----------- |
| `ndk.zaps` | `Zaps` | Zap requests, invoices and receipts (pay with `Nwc.zap`, see wallets.md) |
| `ndk.search` | `Search` | NIP-50 relay search |
| `ndk.fetchedRanges` | `FetchedRanges` | Track fetched time ranges per relay |
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

```dart
final metadata = await ndk.metadata.loadMetadata(pubkey);
print(metadata?.name);
print(metadata?.picture);
print(metadata?.nip05);
```

## Follows

```dart
final contactList = await ndk.follows.getContactList(pubkey);
contactList?.contacts; // List<Contact>
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
