## 0.1.0

 - Initial release. `cleanRelayUrl` and `cleanRelayUrls` moved here from `ndk`: the deep import `package:ndk/shared/helpers/relay_helper.dart` is now `package:dostr_relay_url/dostr_relay_url.dart`, and `dostr_core` exports them too.
 - `relayUrlRegex` and the url normalizer behind `cleanRelayUrl` are gone: it builds on `Uri.parse`.
 - `cleanRelayUrl` accepts IPv6 addresses and a query without a path, which it rejected. It drops the fragment, which RFC 6455 forbids in WebSocket urls, where it kept it after a path and rejected the url otherwise. It also rejects a port above 65535.
