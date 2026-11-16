final _wsScheme = RegExp(r'^ws(s?):/{2,}', caseSensitive: false);

final _hostname = RegExp(
  r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$',
);

/// A ws or wss relay url as [cleanRelayUrl] normalizes it, so two relay urls
/// name one relay exactly when they are equal.
///
/// It is a [String], so it goes wherever one does. A [String] becomes one
/// only through [cleanRelayUrl] or [RelayUrl.parse].
extension type const RelayUrl._(String _url) implements String {
  /// Normalizes [url] as [cleanRelayUrl] does, or throws a [FormatException]
  /// if it is not a ws or wss url.
  factory RelayUrl.parse(String url) =>
      cleanRelayUrl(url) ??
      (throw FormatException('Not a ws or wss relay url', url));
}

/// Normalizes a ws or wss relay url, or returns null if it is not one.
///
/// The scheme and host are lowercased, dot segments removed and
/// percent-encodings normalized, as RFC 3986 section 6 describes. The default
/// port, the user info and the fragment, which RFC 6455 forbids in WebSocket
/// urls, are dropped, and so are trailing slashes, as Nostr clients do.
RelayUrl? cleanRelayUrl(String url) {
  final trimmed = url.trim();
  final scheme = _wsScheme.matchAsPrefix(trimmed);
  if (scheme == null) return null;
  final secure = scheme[1]!.isNotEmpty;

  final Uri uri;
  try {
    // Uri only knows the default ports of http and https, shared by ws and wss
    uri = Uri.parse(
      '${secure ? 'https' : 'http'}://${trimmed.substring(scheme.end)}',
    );
    // Uri.parse may defer parsing the port, which throws if it overflows
    if (uri.port == 0 || uri.port > 65535) return null;
  } on FormatException {
    return null;
  }

  // a host name cannot hold ':', so this is an IPv6 literal Uri.parse checked
  final ipv6 = uri.host.contains(':');
  if (!ipv6 && !_hostname.hasMatch(uri.host)) return null;

  final host = ipv6 ? '[${uri.host}]' : uri.host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final query = uri.query.isEmpty ? '' : '?${uri.query}';
  return RelayUrl._('${secure ? 'wss' : 'ws'}://$host$port$path$query');
}

/// The urls of [urls] that [cleanRelayUrl] accepts, normalized.
List<RelayUrl> cleanRelayUrls(Iterable<String> urls) => [
  for (final url in urls) ?cleanRelayUrl(url),
];
