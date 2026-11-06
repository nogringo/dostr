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
| `ndk.ta` / `ndk.trustedAssertions` | `TrustedAssertions` | NIP-85 trusted metrics |

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

Lives in the `ndk_nip17` package: `Dms(ndk)` sends and loads NIP-17 gift-wrapped messages and publishes the DM relay list (kind 10050).

```dart
import 'package:ndk_nip17/ndk_nip17.dart';

final dms = Dms(ndk);

await dms.sendMessage(recipientPubKey: pubkey, content: 'hello');
final conversations = await dms.loadConversations();
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
