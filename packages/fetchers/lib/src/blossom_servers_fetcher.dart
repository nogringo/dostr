import 'package:ndk_core/ndk_core.dart';

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

/// The normalized servers of [serverList], a `kind:10063`: its http(s)
/// `server` tags, each once, most trusted first.
List<String> blossomServersOf(Nip01Event serverList) => {
  for (final tag in serverList.tags)
    if (tag.length > 1 && tag[0] == 'server') ?_cleanServerUrl(tag[1]),
}.toList();

final _trailingSlashes = RegExp(r'/+$');

String? _cleanServerUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      !(uri.isScheme('https') || uri.isScheme('http')) ||
      uri.host.isEmpty) {
    return null;
  }
  return uri.normalizePath().toString().replaceFirst(_trailingSlashes, '');
}
