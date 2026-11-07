import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_url_set/ndk_url_set.dart';

/// How many inbox relays of each tagged pubkey [broadcastUrlSet] sends to.
const int kMaxInboxRelaysToBroadcast = 5;

const int _kContactListKind = 3;
const int _kGiftWrapKind = 1059;

/// Where [event] goes when its broadcast is given no relays:
/// - the author's outbox, or [bootstrapRelays] once the author is known to
///   have no NIP-65
/// - the first [kMaxInboxRelaysToBroadcast] inbox relays
///   of each `p` tag, except on a contact list
/// - for a gift wrap, only the DM relays of each `p` tag, since its author is
///   a random key
UrlSet broadcastUrlSet(
  Nip01Event event, {
  required List<String> bootstrapRelays,
}) {
  final tagged = event.pTags.toSet();
  if (event.kind == _kGiftWrapKind) {
    return UrlSet.union([for (final p in tagged) UrlSet.dm(p)]);
  }
  return UrlSet.union([
    UrlSet.fallback([
      UrlSet.outbox(event.pubKey),
      UrlSet.explicit(bootstrapRelays),
    ]),
    if (event.kind != _kContactListKind)
      for (final p in tagged)
        UrlSet.first(kMaxInboxRelaysToBroadcast, UrlSet.inbox(p)),
  ]);
}
