## 0.1.0

 - Initial release. `cleanRelayUrl` and `cleanRelayUrls` moved here from `ndk`: the deep import `package:ndk/shared/helpers/relay_helper.dart` is now `package:dostr_relay_url/dostr_relay_url.dart`, and `dostr_core` exports them too.
 - `cleanRelayUrl` returns a `RelayUrl`, an extension type on `String` that only it, `RelayUrl.parse` and `RelayUrl.tryParse` make, and `cleanRelayUrls` a `List<RelayUrl>`. Code that read them as `String`s keeps working.
 - `RelayUrl.tryParse` does what `cleanRelayUrl` does, and `RelayUrl.parse` throws a `FormatException` where they return null.
 - `cleanRelayUrls` takes an `Iterable<String>`, where it took a `List<String>`.
 - `relayUrlRegex` and the url normalizer behind `cleanRelayUrl` are gone: it builds on `Uri.parse`.
 - `cleanRelayUrl` accepts IPv6 addresses and a query without a path, which it rejected. It drops the fragment, which RFC 6455 forbids in WebSocket urls, where it kept it after a path and rejected the url otherwise. It also rejects port 0 and a port above 65535. It drops the trailing dot of a fully qualified host, where it rejected the url.
