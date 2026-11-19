import 'package:dostr_blossom_url/dostr_blossom_url.dart';
import 'package:dostr_core/dostr_core.dart';

import 'outbox_fetcher.dart';

/// Fetches users' Blossom server lists, `kind:10063` (BUD-03), from their
/// write relays, which [nip65Fetcher] finds, and from [relays].
class BlossomServersFetcher extends OutboxFetcher {
  BlossomServersFetcher({
    required super.reqs,
    super.nip65Fetcher,
    super.relays,
    super.timeout,
    super.cache,
    super.checks,
    super.maxAge,
    super.batchWindow,
  }) : super(kind: 10063, name: 'blossom-servers');
}

/// The servers of [serverList], a `kind:10063`: its `server` tags that
/// [BlossomServerUrl.tryParse] accepts, normalized, each once, most trusted
/// first.
List<BlossomServerUrl> blossomServersOf(Nip01Event serverList) => {
  for (final tag in serverList.tags)
    if (tag.length > 1 && tag[0] == 'server')
      ?BlossomServerUrl.tryParse(tag[1]),
}.toList();
