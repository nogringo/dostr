final _extraSlashes = RegExp(r'^(wss?:)/{3,}', caseSensitive: false);

final _hostname = RegExp(
  r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$',
);

/// Normalizes a ws or wss relay url as RFC 3986 section 6 describes, or
/// returns null if it is not one.
///
/// The default port, trailing slashes, the user info and the fragment, which
/// RFC 6455 forbids in WebSocket urls, are dropped.
String? cleanRelayUrl(String url) {
  final Uri uri;
  try {
    // Uri.parse lowercases the scheme and host, removes dot segments and
    // normalizes percent-encodings.
    uri = Uri.parse(
      url.trim().replaceFirstMapped(_extraSlashes, (m) => '${m[1]}//'),
    );
  } on FormatException {
    return null;
  }

  final scheme = uri.scheme;
  if (scheme != 'ws' && scheme != 'wss') return null;
  // a host name cannot hold ':', so this is an IPv6 literal Uri.parse checked
  final ipv6 = uri.host.contains(':');
  if (!ipv6 && !_hostname.hasMatch(uri.host)) return null;
  if (uri.port > 65535) return null;

  final host = ipv6 ? '[${uri.host}]' : uri.host;
  final defaultPort = scheme == 'wss' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final query = uri.query.isEmpty ? '' : '?${uri.query}';
  return '$scheme://$host$port$path$query';
}

/// The urls of [urls] that [cleanRelayUrl] accepts, normalized.
List<String> cleanRelayUrls(List<String> urls) => [
  for (final url in urls) ?cleanRelayUrl(url),
];
