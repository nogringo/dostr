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

RelayUrl.tryParse('WSS://Relay.Primal.NET:443/'); // wss://relay.primal.net
RelayUrl.tryParse('https://relay.primal.net'); // null
RelayUrl.parse('https://relay.primal.net'); // throws a FormatException
RelayUrl.fromUserInput('relay.primal.net'); // wss://relay.primal.net
RelayUrl.fromUserInput('https://relay.primal.net'); // wss://relay.primal.net
RelayUrl.fromUserInput('npub1abc'); // null
```

`RelayUrl.tryParse` normalizes a `ws` or `wss` url, or returns null if it is not one:

- The scheme and host are lowercased, dot segments removed and percent-encodings normalized, as RFC 3986 section 6 describes.
- The default port (443 for `wss`, 80 for `ws`) is dropped.
- Repeated slashes in the path are merged and a trailing one dropped, as Nostr clients do, although RFC 3986 does not make `/a//b/` and `/a/b` equivalent.
- The user info and the fragment, which RFC 6455 forbids in WebSocket urls, are dropped.
- The trailing dot of a fully qualified host, as in `wss://relay.primal.net.`, is dropped.
- Extra slashes after the scheme, as in `wss:///relay.primal.net`, are fixed.
- IPv6 addresses and queries are kept.
- A host name may hold `_`, as browsers allow, although RFC 1123 forbids it.

`RelayUrl.parse` does the same, but throws a `FormatException` where `RelayUrl.tryParse` returns null.

For a list, `urls.map(RelayUrl.tryParse).nonNulls` keeps the relay urls, normalized, in their order.
It does not deduplicate them: `toSet()` does.

## The `RelayUrl` type

`RelayUrl.tryParse` and `RelayUrl.parse` return a `RelayUrl`, an extension type on `String`.
A `RelayUrl` goes wherever a `String` does, but a `String` becomes one only through `RelayUrl.tryParse`, `RelayUrl.parse` and `RelayUrl.fromUserInput`.
An API that takes a `RelayUrl` thus never needs to normalize it again.

```dart
void connect(RelayUrl url) {}

connect(RelayUrl.parse('wss://relay.primal.net/'));
connect('wss://relay.primal.net'); // compile error
```

A cast is the one way around it, and nothing checks it, since an extension type is gone at run time: `'WSS://Relay.Primal.NET' as RelayUrl` succeeds.

## Text a person typed

`RelayUrl.fromUserInput` is for a relay url a person typed in a text field.
It reads a url without a scheme as a `wss` url, and an `http` or `https` url as a `ws` or `wss` one, as Nostr clients do, then normalizes it as `RelayUrl.tryParse` does.
Do not use it on urls from events or other programs: there, an `https` url is not a relay url.

Without a scheme, the host must be `localhost`, an IP address or a name holding a dot.
So a key pasted in the wrong field, or a scheme missing its colon as in `wss//relay.primal.net`, gives null rather than a relay on host `npub1...` or `wss`.
A pasted `nsec1...` would otherwise reach the DNS resolver as a host name.
With a scheme, as in `ws://relay:7777`, a single-label host is kept.

## Limits

Some spellings of one relay still give two urls:

- An IPv6 address is not rewritten in its RFC 5952 form: `wss://[2001:0db8::1]` and `wss://[2001:db8::1]` stay apart.
- An IPv4 address is not rewritten in its canonical form, as browsers do: `wss://127.000.000.001`, `wss://2130706433` and `wss://127.0.0.1` stay apart.
- The query is kept as given: `?a=1&b=2` and `?b=2&a=1` stay apart.

Some urls are rejected although a client could reach them:

- A host with non-ASCII characters: give its punycode form, starting with `xn--`.
