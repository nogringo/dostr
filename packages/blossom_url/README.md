# dostr_blossom_url

Normalization of Blossom server urls, in pure Dart with no dependency.

A server list may spell one server several ways: `https://Blossom.Primal.NET`, `https://blossom.primal.net/`, `https://blossom.primal.net:443`.
Normalized, they are one url, so a client asks each server once and compares servers as strings.

## Install

```yaml
dependencies:
  dostr_blossom_url: ^0.1.0
```

[`dostr_blossom`](https://pub.dev/packages/dostr_blossom) exports this whole package too.

## Usage

```dart
import 'package:dostr_blossom_url/dostr_blossom_url.dart';

cleanBlossomServerUrl('HTTPS://Blossom.Primal.NET:443/'); // https://blossom.primal.net
cleanBlossomServerUrl('wss://relay.primal.net'); // null
cleanBlossomServerUrls(['https://cdn.example.com/', 'not a url']); // [https://cdn.example.com]
BlossomServerUrl.parse('wss://relay.primal.net'); // throws a FormatException
```

`cleanBlossomServerUrl` normalizes an `http` or `https` url, or returns null if it is not one:

- The scheme and host are lowercased, dot segments removed and percent-encodings normalized, as RFC 3986 section 6 describes.
- The default port (443 for `https`, 80 for `http`) is dropped.
- Trailing slashes are dropped, since a client puts its own slash before an endpoint: `https://cdn.example.com/` serves its uploads at `https://cdn.example.com/upload`.
- The fragment, which a client never sends to the server, is dropped.
- Extra slashes after the scheme, as in `https:///cdn.example.com`, are fixed.
- IPv6 addresses and paths are kept, although BUD-01 serves every endpoint from the root of the domain.

It rejects two kinds of urls a client could still send requests to:

- A url with user info, as in `https://user:pass@cdn.example.com`: RFC 9110 section 4.2.4 asks a client to treat it as an error in a url from someone else, such as a server list, since it can hide the real host.
- A url with a query, as in `https://cdn.example.com?token=abc`: the endpoint paths could not follow it.

`cleanBlossomServerUrls` keeps the urls of a list that `cleanBlossomServerUrl` accepts, normalized, in their order.
It does not deduplicate them.

## The `BlossomServerUrl` type

`cleanBlossomServerUrl` returns a `BlossomServerUrl`, an extension type on `String`.
It goes wherever a `String` does, but a `String` becomes one only through `cleanBlossomServerUrl` or `BlossomServerUrl.parse`.
An API that takes a `BlossomServerUrl` thus never needs to normalize it again.

```dart
void upload(BlossomServerUrl server) {}

upload(BlossomServerUrl.parse('https://cdn.example.com/'));
upload('https://cdn.example.com'); // compile error
```

## Limits

Some spellings of one server still give two urls:

- An IPv6 address is not rewritten in its RFC 5952 form: `https://[2001:0db8::1]` and `https://[2001:db8::1]` stay apart.
- Repeated slashes in the path, as in `https://cdn.example.com//media`, are kept.

Some urls are rejected although a client could reach them:

- A host ending with a dot, as in `https://cdn.example.com.`.
- A host with non-ASCII characters: give its punycode form, starting with `xn--`.
