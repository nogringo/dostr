import 'outbox_fetcher.dart';

/// Fetches users' `kind:0` metadata from their write relays, which
/// [nip65Fetcher] finds, and from [relays].
class MetadataFetcher extends OutboxFetcher {
  MetadataFetcher({
    required super.reqs,
    super.nip65Fetcher,
    super.relays,
    super.timeout,
  }) : super(kind: 0, name: 'metadata');
}
