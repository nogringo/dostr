# ndk_http

The HTTP data source that NDK packages share, on top of
[`http`](https://pub.dev/packages/http). Every call turns a non-2xx response
into an `HttpRequestException` that keeps the status code, the body and the
response headers (names in lowercase), so a caller can read a reason such as
Blossom's `x-reason`.

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
  'https://example.com/.well-known/nostr.json?name=bob',
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
`getStream` downloads the same way.

## Coming from `ndk`

`package:ndk/data_layer/data_sources/http_request.dart` is now
`package:ndk_http/ndk_http.dart`.
