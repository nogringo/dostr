# ndk_http

The HTTP data source that NDK packages share, on top of
[`http`](https://pub.dev/packages/http). Every call turns a non-2xx response
into an `HttpRequestException` that keeps the method, the status code, the
body and the response headers (names in lowercase), so a caller can read a
reason such as Blossom's `x-reason`.

A package that talks HTTP the way NDK does, such as
[`ndk_blossom`](https://pub.dev/packages/ndk_blossom) or
[`ndk_cashu`](https://pub.dev/packages/ndk_cashu), only needs this package,
not `ndk`.

## Install

```yaml
dependencies:
  ndk_http: ^0.1.0
```

## Usage

```dart
import 'package:http/http.dart' as http;
import 'package:ndk_http/ndk_http.dart';

final ds = HttpRequestDS(http.Client());

final json = await ds.jsonRequest(
  Uri.parse('https://example.com/.well-known/nostr.json?name=bob'),
  timeout: const Duration(seconds: 5),
);
```

`jsonRequest` uses the url as given, so the caller picks the scheme, and
decodes the body as UTF-8. `abortPending` aborts every request still in
flight without closing the client.

`putStream` uploads a stream without loading it into memory: the body is read
only as fast as the connection sends it, and `UploadProgress` follows the bytes
as they go out. The upload starts when the stream is listened to, cancelling
the subscription aborts it, and the last event carries the response.
`getStream` downloads the same way, at the pace the listener reads the
stream.

On the web, `BrowserClient` reads the whole body before it sends anything, so
`putStream` holds the upload in memory there and its progress reaches the total
before the bytes go out.

## Timeouts

Every request takes a `timeout` that bounds it as a whole. `getStream` and
`putStream` take an `idleTimeout` instead: it only counts the time without data
moving, so it never cuts a large transfer short, and a paused download does not
count. Either one ends the request with a `TimeoutException`, while
`abortPending` ends it with a `RequestAbortedException`, so a caller can tell
them apart.

## Coming from `ndk`

`package:ndk/data_layer/data_sources/http_request.dart` is now
`package:ndk_http/ndk_http.dart`. Besides the import:

- `jsonRequest` takes a `Uri` and no longer forces `https`.
- A timeout throws `TimeoutException` instead of `RequestAbortedException`.
- `HttpRequestException` has a required `method`.
- `UploadProgress.error` is gone: a failed upload is an error on the stream.
- `headers` are typed `Map<String, String>` and optional on every method.
