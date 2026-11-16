## 0.1.0

 - Initial release. The relay url normalization of `ndk` moved here: the deep import `package:ndk/shared/helpers/relay_helper.dart` is now `package:dostr_relay_url/dostr_relay_url.dart`, and `dostr_core` exports it too.
 - `cleanRelayUrl(url)` is now `RelayUrl.tryParse(url)`, as in `Uri.tryParse`, and `cleanRelayUrls(urls)` is gone: `urls.map(RelayUrl.tryParse).nonNulls` replaces it.
 - `RelayUrl.tryParse` returns a `RelayUrl`, an extension type on `String` that only it, `RelayUrl.parse` and `RelayUrl.fromUserInput` make, short of a cast. Code that read the urls as `String`s keeps working.
 - `RelayUrl.parse` does what `RelayUrl.tryParse` does, but throws a `FormatException` where it returns null.
 - `RelayUrl.fromUserInput` normalizes a relay url a person typed: it reads a url without a scheme as a `wss` url, and an `http` or `https` url as a `ws` or `wss` one. Without a scheme, the host must be `localhost`, an IP address or a name holding a dot.
 - `relayUrlRegex` and the url normalizer behind `cleanRelayUrl` are gone: `RelayUrl.tryParse` builds on `Uri.parse`.
 - `RelayUrl.tryParse` accepts IPv6 addresses, a query without a path and a host name holding `_`, which `cleanRelayUrl` rejected. It drops the fragment, which RFC 6455 forbids in WebSocket urls, where `cleanRelayUrl` kept it after a path and rejected the url otherwise. It also rejects port 0 and a port above 65535. It drops the trailing dot of a fully qualified host, where `cleanRelayUrl` rejected the url. It merges repeated slashes in the path, where `cleanRelayUrl` kept them.
