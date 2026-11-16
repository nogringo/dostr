final _wsScheme = RegExp(r'^ws(s?):/{2,}', caseSensitive: false);

final _httpScheme = RegExp(r'^http(s?)://', caseSensitive: false);

final _anyScheme = RegExp(r'^[a-z][a-z0-9+.-]*:/', caseSensitive: false);

// browsers accept '_', although RFC 1123 host names forbid it
final _hostname = RegExp(
  r'^[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?(\.[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?)*$',
);

final _repeatedSlashes = RegExp('/{2,}');

/// A ws or wss relay url as [RelayUrl.tryParse] normalizes it, so two relay
/// urls name one relay exactly when they are equal.
///
/// It is a [String], so it goes wherever one does. A [String] becomes one
/// only through [RelayUrl.tryParse], [RelayUrl.parse] or
/// [RelayUrl.fromUserInput], or through a cast, which nothing checks since
/// the type is gone at run time.
extension type const RelayUrl._(String _url) implements String {
  /// Normalizes [url] as [tryParse] does, or throws a [FormatException] if it
  /// is not a ws or wss url.
  factory RelayUrl.parse(String url) =>
      tryParse(url) ??
      (throw FormatException('Not a ws or wss relay url', url));

  /// Normalizes a ws or wss relay url, or returns null if it is not one.
  ///
  /// The scheme and host are lowercased, dot segments removed and
  /// percent-encodings normalized, as RFC 3986 section 6 describes. The
  /// default port, the user info and the fragment, which RFC 6455 forbids in
  /// WebSocket urls, are dropped. Repeated slashes in the path are merged and
  /// a trailing one dropped, as Nostr clients do. A fully qualified host name
  /// loses its trailing dot.
  static RelayUrl? tryParse(String url) {
    final trimmed = url.trim();
    final scheme = _wsScheme.matchAsPrefix(trimmed);
    if (scheme == null) return null;
    final secure = scheme[1]!.isNotEmpty;

    final Uri uri;
    try {
      // Uri knows only the http and https default ports, which ws and wss share
      uri = Uri.parse(
        '${secure ? 'https' : 'http'}://${trimmed.substring(scheme.end)}',
      );
      // Uri.parse may defer parsing the port, which throws if it overflows
      if (uri.port == 0 || uri.port > 65535) return null;
    } on FormatException {
      return null;
    }

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
    var path = uri.path.replaceAll(_repeatedSlashes, '/');
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    final query = uri.query.isEmpty ? '' : '?${uri.query}';
    return RelayUrl._('${secure ? 'wss' : 'ws'}://$host$port$path$query');
  }

  /// Normalizes [input], a relay url a person typed, or returns null if it is
  /// not one.
  ///
  /// Unlike [tryParse], it reads a url without a scheme as a wss url, and an
  /// http or https url as a ws or wss one, as Nostr clients do. A url without
  /// a scheme must name localhost, an IP address or a host name holding a
  /// dot, so a pasted key or a scheme missing its colon, as in
  /// `wss//relay.primal.net`, is not read as a host.
  static RelayUrl? fromUserInput(String input) {
    final trimmed = input.trim();
    final http = _httpScheme.matchAsPrefix(trimmed);
    if (http != null) {
      return tryParse('ws${http[1]}://${trimmed.substring(http.end)}');
    }
    if (_anyScheme.hasMatch(trimmed)) return tryParse(trimmed);

    final url = tryParse('wss://$trimmed');
    if (url == null) return null;
    final host = Uri.parse(url).host;
    final ipv6 = host.contains(':');
    return host.contains('.') || ipv6 || host == 'localhost' ? url : null;
  }
}
