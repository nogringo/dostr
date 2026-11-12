/// Relay and Blossom server sets for Nostr, described as a [UrlSet] so they
/// can be stored offline and resolved later from the lists accounts publish,
/// and the normalization of relay urls.
library;

export 'src/relay_helper.dart' show cleanRelayUrl, cleanRelayUrls;
export 'src/url_list_checks.dart';
export 'src/url_set.dart';
