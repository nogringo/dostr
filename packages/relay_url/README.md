# dostr_relay_url

Normalization of Nostr relay urls, in pure Dart with no dependency.

A relay list may spell one relay several ways: `wss://Relay.Primal.NET`, `wss://relay.primal.net/`, `wss://relay.primal.net:443`.
Normalized, they are one url, so a client connects once and compares relays as strings.

## Install

```yaml
dependencies:
  dostr_relay_url: ^0.1.0
```

[`dostr_core`](https://pub.dev/packages/dostr_core) exports this whole package too.

## Usage

```dart
import 'package:dostr_relay_url/dostr_relay_url.dart';

cleanRelayUrl('WSS://Relay.Primal.NET:443/'); // wss://relay.primal.net
cleanRelayUrl('https://relay.primal.net'); // null
cleanRelayUrls(['wss://relay.ditto.pub/', 'not a url']); // [wss://relay.ditto.pub]
RelayUrl.tryParse('https://relay.primal.net'); // null
RelayUrl.parse('https://relay.primal.net'); // throws a FormatException
```

`cleanRelayUrl` normalizes a `ws` or `wss` url, or returns null if it is not one:

- The scheme and host are lowercased, dot segments removed and percent-encodings normalized, as RFC 3986 section 6 describes.
- The default port (443 for `wss`, 80 for `ws`) is dropped.
- Trailing slashes are dropped, as Nostr clients do, although RFC 3986 does not make `/path/` and `/path` equivalent.
- The user info and the fragment, which RFC 6455 forbids in WebSocket urls, are dropped.
- The trailing dot of a fully qualified host, as in `wss://relay.primal.net.`, is dropped.
- Extra slashes after the scheme, as in `wss:///relay.primal.net`, are fixed.
- IPv6 addresses and queries are kept.

`cleanRelayUrls` keeps the urls of a list that `cleanRelayUrl` accepts, normalized, in their order.
It does not deduplicate them.

## The `RelayUrl` type

`cleanRelayUrl` returns a `RelayUrl`, an extension type on `String`.
`RelayUrl.tryParse` does what `cleanRelayUrl` does, and `RelayUrl.parse` throws a `FormatException` where they return null.
A `RelayUrl` goes wherever a `String` does, but a `String` becomes one only through these three.
An API that takes a `RelayUrl` thus never needs to normalize it again.

```dart
void connect(RelayUrl url) {}

connect(RelayUrl.parse('wss://relay.primal.net/'));
connect('wss://relay.primal.net'); // compile error
```

## Limits

Some spellings of one relay still give two urls:

- An IPv6 address is not rewritten in its RFC 5952 form: `wss://[2001:0db8::1]` and `wss://[2001:db8::1]` stay apart.
- Repeated slashes in the path, as in `wss://relay.example.com//nostr`, are kept.
- The query is kept as given: `?a=1&b=2` and `?b=2&a=1` stay apart.

Some urls are rejected although a client could reach them:

- A host with non-ASCII characters: give its punycode form, starting with `xn--`.
