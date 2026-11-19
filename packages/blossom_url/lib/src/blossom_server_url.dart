final _httpScheme = RegExp(r'^http(s?):/{2,}', caseSensitive: false);

final _anyScheme = RegExp(r'^[a-z][a-z0-9+.-]*:/', caseSensitive: false);

// browsers accept '_', although RFC 1123 host names forbid it
final _hostname = RegExp(
  r'^[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?(\.[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?)*$',
);

final _trailingSlashes = RegExp(r'/+$');

/// An http or https Blossom server url as [BlossomServerUrl.tryParse]
/// normalizes it, so two server urls name one server exactly when they are
/// equal.
///
/// It is a [String], so it goes wherever one does. A [String] becomes one
/// only through [BlossomServerUrl.tryParse], [BlossomServerUrl.parse] or
/// [BlossomServerUrl.fromUserInput], or through a cast, which nothing checks
/// since the type is gone at run time.
extension type const BlossomServerUrl._(String _url) implements String {
  /// Normalizes [url] as [tryParse] does, or throws a [FormatException] if it
  /// is not a Blossom server url.
  factory BlossomServerUrl.parse(String url) =>
      tryParse(url) ??
      (throw FormatException('Not an http or https Blossom server url', url));

  /// Normalizes an http or https Blossom server url, or returns null if it is
  /// not one.
  ///
  /// The scheme and host are lowercased, dot segments removed and
  /// percent-encodings normalized, as RFC 3986 section 6 describes. The
  /// default port, the fragment, trailing slashes and the trailing dot of a
  /// fully qualified host name are dropped. A url with user info, which RFC
  /// 9110 section 4.2.4 deprecates, or with a query, which the endpoint paths
  /// could not follow, is not a server url.
  static BlossomServerUrl? tryParse(String url) {
    final trimmed = url.trim();
    final match = _httpScheme.matchAsPrefix(trimmed);
    if (match == null) return null;
    final scheme = match[1]!.isEmpty ? 'http' : 'https';

    final Uri uri;
    try {
      uri = Uri.parse('$scheme://${trimmed.substring(match.end)}');
      // Uri.parse may defer parsing the port, which throws if it overflows
      if (uri.port == 0 || uri.port > 65535) return null;
    } on FormatException {
      return null;
    }
    if (uri.userInfo.isNotEmpty || uri.query.isNotEmpty) return null;

    // Uri.host keeps the brackets of an IPvFuture literal, never of an IPv6 one
    if (uri.host.startsWith('[')) return null;
    // a host name cannot hold ':', so this is an IPv6 literal Uri.parse checked
    final ipv6 = uri.host.contains(':');
    final name = uri.host.endsWith('.')
        ? uri.host.substring(0, uri.host.length - 1)
        : uri.host;
    if (!ipv6 && !_hostname.hasMatch(name)) return null;

    final host = ipv6 ? '[${uri.host}]' : name;
    final port = uri.hasPort ? ':${uri.port}' : '';
    final path = uri.path.replaceFirst(_trailingSlashes, '');
    return BlossomServerUrl._('$scheme://$host$port$path');
  }

  /// Normalizes [input], a server url a person typed, or returns null if it
  /// is not one.
  ///
  /// Unlike [tryParse], it reads a url without a scheme as an https url. A url
  /// without a scheme must name localhost, an IP address or a host name
  /// holding a dot, so a pasted key or a scheme missing its colon, as in
  /// `https//cdn.example.com`, is not read as a host.
  static BlossomServerUrl? fromUserInput(String input) {
    final trimmed = input.trim();
    if (_anyScheme.hasMatch(trimmed)) return tryParse(trimmed);

    final url = tryParse('https://$trimmed');
    if (url == null) return null;
    final host = Uri.parse(url).host;
    final ipv6 = host.contains(':');
    return host.contains('.') || ipv6 || host == 'localhost' ? url : null;
  }
}
