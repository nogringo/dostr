import 'package:ndk/ndk.dart';
import 'package:ndk_nip17/ndk_nip17.dart';

Dms dmsFor(Ndk ndk) => Dms(
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
