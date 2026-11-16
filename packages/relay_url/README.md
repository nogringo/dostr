# dostr_relay_url

Normalization of Nostr relay urls, in pure Dart with no dependency.

A relay list may spell one relay several ways: `wss://Relay.Primal.NET`, `wss://relay.primal.net/`, `wss://relay.primal.net:443`.
Normalized, they are one url, so a client connects once and compares relays as strings.

## Install

```yaml
dependencies:
  dostr_relay_url: ^0.1.0
```

[`dostr_core`](https://pub.dev/packages/dostr_core) exports both functions too.

## Usage

```dart
import 'package:dostr_relay_url/dostr_relay_url.dart';

cleanRelayUrl('WSS://Relay.Primal.NET:443/'); // wss://relay.primal.net
cleanRelayUrl('https://relay.primal.net'); // null
cleanRelayUrls(['wss://relay.ditto.pub/', 'not a url']); // [wss://relay.ditto.pub]
```

`cleanRelayUrl` normalizes a url as RFC 3986 section 6 describes, or returns null if it is not a `ws` or `wss` url:

- The scheme and host are lowercased, dot segments removed and percent-encodings normalized.
- The default port (443 for `wss`, 80 for `ws`) and trailing slashes are dropped.
- The user info and the fragment, which RFC 6455 forbids in WebSocket urls, are dropped.
- Extra slashes after the scheme, as in `wss:///relay.primal.net`, are fixed.
- IPv6 addresses and queries are kept.

`cleanRelayUrls` keeps the urls of a list that `cleanRelayUrl` accepts, normalized, in their order.
It does not deduplicate them.
