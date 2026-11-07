# ndk_nip17

[NIP-17](https://github.com/nostr-protocol/nips/blob/master/17.md) private direct messages for [NDK](https://pub.dev/packages/ndk): gift-wrapped text (kind `14`) and encrypted file (kind `15`) messages, conversations grouped by peer, and the DM relay list (kind `10050`).

It does not depend on `ndk`. It wraps through [`ndk_nip59`](https://pub.dev/packages/ndk_nip59), takes its accounts and auth policies from [`ndk_signer`](https://pub.dev/packages/ndk_signer), and asks you how to reach the relays and the cache. NDK exposes it, wired to its relays and cache, as `ndk.dms`: build it yourself, as below, only to wire it differently.

## Install

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_nip17: ^0.1.0
```

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_nip17/ndk_nip17.dart';

final ndk = Ndk.defaultConfig();
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

// where the logged-in account receives its DMs
await dms.publishDmRelays(relayUrlsOrdered: ['wss://inbox.example.com']);

await dms.sendMessage(recipientPubKey: pubkey, content: 'hello');

final conversations = await dms.loadConversations();
final cached = await dms.loadConversationsSnapshot();
```

`Dms` signs, decrypts and authenticates with the logged-in account of `accounts`. `getDmRelays` reads a user's DM relay list, `query` fetches events from the relays (and the cache unless `cacheRead` is false), `publish` sends a signed event, and `loadCachedGiftWraps` answers `loadConversationsSnapshot` from the cache alone. Decrypted gift wraps are kept by the cache of `giftWrap`. Sending fails when the sender or the recipient has no DM relay list.

More in [example/](example/) and the [DM docs](https://dart-nostr.com/usecases/dms/).
