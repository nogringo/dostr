import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_url_set/ndk_url_set.dart';

import '../../../config/broadcast_defaults.dart';
import 'package:ndk_follows/ndk_follows.dart';
import 'package:ndk_nip59/ndk_nip59.dart';

/// Where [event] goes when its broadcast is given no relays:
/// - the author's outbox, or [bootstrapRelays] once the author is known to
///   have no NIP-65
/// - the first [BroadcastDefaults.MAX_INBOX_RELAYS_TO_BROADCAST] inbox relays
///   of each `p` tag, except on a contact list
/// - for a gift wrap, only the DM relays of each `p` tag, since its author is
///   a random key
UrlSet broadcastUrlSet(
  Nip01Event event, {
  required List<String> bootstrapRelays,
}) {
  final tagged = event.pTags.toSet();
  if (event.kind == GiftWrap.kGiftWrapEventkind) {
    return UrlSet.union([for (final p in tagged) UrlSet.dm(p)]);
  }
  return UrlSet.union([
    UrlSet.fallback([
      UrlSet.outbox(event.pubKey),
      UrlSet.explicit(bootstrapRelays),
    ]),
    if (event.kind != ContactList.kKind)
      for (final p in tagged)
        UrlSet.first(
          BroadcastDefaults.MAX_INBOX_RELAYS_TO_BROADCAST,
          UrlSet.inbox(p),
        ),
  ]);
}
