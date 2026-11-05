import 'package:ndk_core/ndk_core.dart';

import 'outbox_fetcher.dart';

/// Fetches users' NIP-17 DM relay lists, `kind:10050`, from their write
/// relays, which [nip65Fetcher] finds, and from [relays].
class DmRelaysFetcher extends OutboxFetcher {
  DmRelaysFetcher({
    required super.reqs,
    super.nip65Fetcher,
    super.relays,
    super.timeout,
  }) : super(kind: 10050, name: 'dm-relays');
}

/// The normalized relays of [dmRelayList], a `kind:10050`: its `relay` tags,
/// each once, in order.
List<String> dmRelaysOf(Nip01Event dmRelayList) => cleanRelayUrls([
  for (final tag in dmRelayList.tags)
    if (tag.length > 1 && tag[0] == 'relay') tag[1],
]).toSet().toList();
