## 0.1.0

 - Initial release. `cleanRelayUrl` and `cleanRelayUrls` moved here from `ndk`: the deep import `package:ndk/shared/helpers/relay_helper.dart` is now `package:dostr_relay_url/dostr_relay_url.dart`, and `dostr_core` exports them too.
 - `cleanRelayUrl` returns a `RelayUrl`, an extension type on `String` that only it, `RelayUrl.tryParse`, `RelayUrl.parse` and `RelayUrl.fromUserInput` make, short of a cast, and `cleanRelayUrls` a `List<RelayUrl>`. Code that read them as `String`s keeps working.
 - `RelayUrl.tryParse` is `cleanRelayUrl` under the name Dart gives it, as in `Uri.tryParse`.
 - `RelayUrl.parse` does what `cleanRelayUrl` does, but throws a `FormatException` where it returns null.
 - `RelayUrl.fromUserInput` normalizes a relay url a person typed: it reads a url without a scheme as a `wss` url, and an `http` or `https` url as a `ws` or `wss` one. Without a scheme, the host must be `localhost`, an IP address or a name holding a dot.
 - `cleanRelayUrls` takes an `Iterable<String>`, where it took a `List<String>`.
 - `relayUrlRegex` and the url normalizer behind `cleanRelayUrl` are gone: it builds on `Uri.parse`.
 - `cleanRelayUrl` accepts IPv6 addresses, a query without a path and a host name holding `_`, which it rejected. It drops the fragment, which RFC 6455 forbids in WebSocket urls, where it kept it after a path and rejected the url otherwise. It also rejects port 0 and a port above 65535. It drops the trailing dot of a fully qualified host, where it rejected the url. It merges repeated slashes in the path, where it kept them.
