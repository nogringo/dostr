final _httpScheme = RegExp(r'^http(s?):/{2,}', caseSensitive: false);

final _hostname = RegExp(
  r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$',
);

final _trailingSlashes = RegExp(r'/+$');

/// An http or https Blossom server url as [cleanBlossomServerUrl] normalizes
/// it, so two server urls name one server exactly when they are equal.
///
/// It is a [String], so it goes wherever one does. A [String] becomes one
/// only through [cleanBlossomServerUrl] or [BlossomServerUrl.parse].
extension type const BlossomServerUrl._(String _url) implements String {
  /// Normalizes [url] as [cleanBlossomServerUrl] does, or throws a
  /// [FormatException] if it is not a Blossom server url.
  factory BlossomServerUrl.parse(String url) =>
      cleanBlossomServerUrl(url) ??
      (throw FormatException('Not an http or https Blossom server url', url));
}

/// Normalizes an http or https Blossom server url, or returns null if it is
/// not one.
///
/// The scheme and host are lowercased, dot segments removed and
/// percent-encodings normalized, as RFC 3986 section 6 describes. The default
/// port, the fragment and trailing slashes are dropped. A url with user info,
/// which RFC 9110 section 4.2.4 deprecates, or with a query, which the
/// endpoint paths could not follow, is not a server url.
BlossomServerUrl? cleanBlossomServerUrl(String url) {
  final trimmed = url.trim();
  final match = _httpScheme.matchAsPrefix(trimmed);
  if (match == null) return null;
  final scheme = match[1]!.isEmpty ? 'http' : 'https';

  final Uri uri;
  try {
    uri = Uri.parse('$scheme://${trimmed.substring(match.end)}');
  } on FormatException {
    return null;
  }
  if (uri.userInfo.isNotEmpty || uri.query.isNotEmpty) return null;

  // a host name cannot hold ':', so this is an IPv6 literal Uri.parse checked
  final ipv6 = uri.host.contains(':');
  if (!ipv6 && !_hostname.hasMatch(uri.host)) return null;
  if (uri.port == 0 || uri.port > 65535) return null;

  final host = ipv6 ? '[${uri.host}]' : uri.host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.replaceFirst(_trailingSlashes, '');
  return BlossomServerUrl._('$scheme://$host$port$path');
}

/// The urls of [urls] that [cleanBlossomServerUrl] accepts, normalized.
List<BlossomServerUrl> cleanBlossomServerUrls(Iterable<String> urls) => [
  for (final url in urls) ?cleanBlossomServerUrl(url),
];
