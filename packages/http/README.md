# ndk_http

The HTTP data source that NDK packages share, on top of
[`http`](https://pub.dev/packages/http). Every call turns a non-2xx response
into an `HttpRequestException` that keeps the method, the status code, the
body and the response headers (names in lowercase), so a caller can read a
reason such as Blossom's `x-reason`. It is an `http.ClientException`, like the
failure of a request that got no response, so catching `ClientException`
covers both.

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

final ds = NdkHttp(http.Client());

final json = await ds.jsonRequest(
  url: Uri.parse('https://example.com/.well-known/nostr.json?name=bob'),
  timeout: const Duration(seconds: 5),
);
```

`jsonRequest` uses the url as given, so the caller picks the scheme, and
decodes the body as UTF-8. A body that is not a JSON object throws a
`FormatException`. Its `headers` add to `Accept: application/json`, which they
can replace. `abortPending` aborts every request still in flight without
closing the client.

`get`, `head`, `getStream` and `jsonRequest` take `followRedirects`. With it
off, a redirect throws its 3xx as an `HttpRequestException`, except on the web,
where `BrowserClient` fails it with a plain `ClientException`.

`putStream` uploads a stream without loading it into memory: the body is read
only as fast as the connection sends it, and `UploadProgress` follows the bytes
as they go out. The upload starts when the stream is listened to, cancelling
the subscription aborts it, and the last event carries the response. Without
a `contentLength`, its `totalBytes` and `progress` are null.

`postStream` does the same with a POST. For a multipart form, such as a NIP-96
upload, let `http.MultipartRequest` encode it:

```dart
final form = http.MultipartRequest('POST', url)
  ..files.add(http.MultipartFile('file', fileStream, fileLength));
final body = form.finalize();
final progress = ds.postStream(
  url: url,
  body: body,
  headers: form.headers,
  contentLength: form.contentLength,
);
```

`getStream` completes once the status and headers arrive, with an
`http.StreamedResponse` whose `stream` downloads the body at the pace the
listener reads it. Cancelling that subscription aborts the download, and
completing `abortTrigger` aborts it at any point. Read or cancel the body:
until its stream is listened to, the request holds its connection.

On the web, `BrowserClient` reads the whole body before it sends anything, so
`putStream` holds the upload in memory there and its progress reaches the total
before the bytes go out.

## Timeouts

Every request takes a `timeout` that bounds it as a whole. `getStream`,
`putStream` and `postStream` take an `idleTimeout` instead: it only counts the
time without data moving, so it never cuts a large transfer short. A paused
download does not count, but a body nobody listens to yet does. On an upload, the wait for the response after the last byte counts too,
so the timeout must cover the time the server takes to process the body, such
as hashing it. Either one ends the request with a `TimeoutException`, while
`abortPending` ends it with a `RequestAbortedException`, so a caller can tell
them apart.

Timeouts and `abortPending` work by aborting the request, so they need a
client that honors `Abortable.abortTrigger`, as `IOClient`, `BrowserClient`
and `RetryClient` do. With a client that ignores it, a request can outlive its
timeout and keep running after `abortPending`.

## Coming from `ndk`

`package:ndk/data_layer/data_sources/http_request.dart` is now
`package:ndk_http/ndk_http.dart`. Besides the import:

- `HttpRequestDS` is now `NdkHttp`.
- `jsonRequest` takes a named `url`, a `Uri`, and no longer forces `https`.
- `jsonRequest` throws `FormatException` instead of `TypeError` when the body
  is not a JSON object.
- `jsonRequest`'s `headers` add to `Accept: application/json` instead of
  replacing it.
- `getStream` returns a `Future<http.StreamedResponse>` that completes with the
  status and headers. The body is its `stream`, and `abortTrigger` aborts the
  request before the response.
- A timeout throws `TimeoutException` instead of `RequestAbortedException`.
- `HttpRequestException` is a `ClientException` with a required `method`, and
  its `url` string is now `uri`, a `Uri`.
- `UploadProgress.error` is gone: a failed upload is an error on the stream.
- `UploadProgress.totalBytes`, `progress` and `percentage` are null instead of
  0 when the upload has no content length.
- `headers` are typed `Map<String, String>` and optional on every method.
