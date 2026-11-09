/// Fetches a user's `kind:0` metadata, NIP-65 relay list, NIP-17 DM relay
/// list, Blossom server list and `home-relays` list on top of ndk_core,
/// resolves an ndk_url_set `UrlSet` with them, and fetches the events of any
/// filter from where a set resolves.
library;

export 'src/blossom_servers_fetcher.dart';
export 'src/dm_relays_fetcher.dart';
export 'src/event_fetcher.dart';
export 'src/home_relay_list_fetcher.dart';
export 'src/metadata_fetcher.dart';
export 'src/nip65_fetcher.dart';
export 'src/outbox_fetcher.dart';
export 'src/replaceable_events.dart' show defaultIndexerRelays;
export 'src/replaceable_lookup.dart'
    show
        EventFound,
        EventLookup,
        EventNotFound,
        EventUnavailable,
        ReplaceableEventCache;
export 'src/url_lists.dart';
