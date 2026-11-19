# dostr_blossom

[Blossom](https://github.com/hzrd149/blossom) file storage for Nostr: upload, download, mirror, list and delete blobs, on the servers you pick or on a user's server list (kind `10063`).
`Files` wraps it in a simpler API that also takes plain urls.

It signs through [`dostr_signer`](https://pub.dev/packages/dostr_signer), which also gives it its accounts and auth policies, and asks you how to read a user's server list.

## Install

```yaml
dependencies:
  dostr_blossom: ^0.1.0
  dostr_accounts: ^0.1.0
  dostr_bip340: ^0.1.0
  dostr_core: ^0.1.0
  dostr_fetchers: ^0.1.0
```

## Usage

`Blossom` signs as the logged account of an `AuthAccounts`, such as the `Accounts` of [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).
Here the fetchers of [`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers) read a user's server list from their write relays:

```dart
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_blossom/dostr_blossom.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';

final relayManager = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relayManager,
  eventVerifier: Bip340EventVerifier(),
);
final nip65 = Nip65Fetcher(reqs: reqs);
final serverLists = BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65);

final accounts = Accounts(const Bip340SignerFactory());
final blossom = Blossom(
  accounts: accounts,
  signerFactory: const Bip340SignerFactory(),
  getUserServerList: (pubkey) async {
    final serverList = await serverLists.fetch(pubkey);
    return serverList == null ? null : blossomServersOf(serverList);
  },
);

// high level: a Blossom url goes through Blossom, any other url is fetched directly
final files = Files(blossom);
final file = await files.download(
  url: 'https://cdn.hzrd149.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.pdf',
);

// low level: every BUD operation, with the servers you choose
final blob = await blossom.getBlob(
  sha256: 'b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553',
  serverUrls: ['https://cdn.example.com', 'https://blossom.example.com'],
);
print('${blob.mimeType}, ${blob.data.length} bytes');
```

A client that only reads needs none of that: `Files(Blossom())` downloads any blob.

More in [example/](example/).

## Servers

Upload, list and delete use the user's server list (kind `10063`) when no `serverUrls` are given.

A read tries `serverUrls` first.
Given `pubkeyToFetchUserServerList` too, it reads that user's server list only once none of `serverUrls` had the blob, and then tries the servers it did not try yet.
When `serverUrls` names no server url it accepts, it reads that list at once.

Every server url is normalized with `BlossomServerUrl.tryParse`, from [`dostr_blossom_url`](https://pub.dev/packages/dostr_blossom_url), so an operation talks to each server once however the urls spell it, and a trailing slash, as kind `10063` lists often write it, changes nothing.
A url it refuses is skipped, as if it were not there: one with user info, which can hide the real host, one with a query, or one whose scheme is not `http` or `https`.

The authorization events are signed automatically and are valid for five minutes (`Blossom.defaultAuthExpiration`), or for the `authExpiration` passed to the `Blossom` constructor.
An operation that outlives it, such as a long streamed download, signs a new event when a server refuses the expired one.

## Cancelling

Every operation takes an `abortTrigger`, as the requests of `package:http` do.
Once it completes, with a value or an error, that operation ends with a `RequestAbortedException` and tries no other server, while the others go on:

```dart
final cancel = Completer<void>();
final blob = blossom.getBlob(
  sha256: hash,
  serverUrls: servers,
  abortTrigger: cancel.future,
);
cancel.complete(); // the screen showing it closed
```

Cancelling the subscription to an upload stream, such as `uploadBlobFromFile`, aborts that upload too.
`blossom.abortPending()` ends every operation in flight the same way, and the instance stays usable.
An operation waiting on a signer, on relays or on the `AuthHandler` ends once that wait is over, without sending anything more.

## HTTP client

`Blossom` talks to the servers through an `http.Client` of its own, or through the `httpClient` you give it, such as a `cupertino_http` or `cronet_http` client in a Flutter app.
`blossom.close()` ends what is in flight and closes the client it made.
A client you gave it stays open, since it is yours to close.

## Errors

A read that no server served (`getBlob`, `checkBlob`, `getBlobStream`, `downloadBlobToFile`, `listBlobs`) throws a `BlossomRequestException`.
Its `errors` say why each server failed, by server url, in the order they were tried: an `HttpRequestException` carries the status the server answered with.

```dart
try {
  await blossom.getBlob(sha256: hash, serverUrls: servers);
} on BlossomRequestException catch (e) {
  if (e.notFound) {
    // no server has the blob
  }
}
```

A download checks that the bytes hash to the sha256 it asked for.
A server that serves anything else fails with a `BlossomHashMismatchException`: `getBlob` moves on to the next server, while `getBlobStream` ends with it and `downloadBlobToFile` throws it without saving anything.

An operation with no server to talk to throws a `BlossomNoServerListException` before sending anything: the user has no server list (kind `10063`), or one without a server url `BlossomServerUrl.tryParse` accepts, or the call named no server url it accepts and no pubkey to read a list for.
Its `pubkey` says whose list is missing.

Writes report each server in their results instead: `BlobUploadResult` and `BlobDeleteResult` say whether that server succeeded, and why not.

Every server url these results and exceptions give is a `BlossomServerUrl`, normalized, so it compares equal to the url `BlossomServerUrl.tryParse` makes from any spelling of that server.

## Server authentication (BUD-01)

Some servers only serve a private blob, or only accept an upload, from a client that signed a kind `24242` event.
The `auth` parameter says which identity a server may learn, with the same `AuthPolicy` as relays use for [NIP-42](https://pub.dev/packages/dostr_core#nip-42-authentication):

```dart
final response = await blossom.getBlob(
  sha256: hash,
  serverUrls: ['https://cdn.example.com'],
  auth: AuthPolicy.allow(account),
);
```

| policy | what goes out | what a server learns |
| --- | --- | --- |
| `AuthPolicy.never()` | no authorization, ever | nothing. A server that refuses without one simply does not serve the request |
| `AuthPolicy.allow(a)` | nothing at first, then the signed event once a server answered 401 | who you are, but only after that server asked |
| `AuthPolicy.require(a)` | the signed event on the first request | who you are, as soon as you ask it for anything |

The account does not have to be one of `accounts`.
`allow` costs a refused HTTP round trip, and for an upload a body sent twice, so prefer `require` when the server is known to ask.
If `require` names an account that cannot sign, nothing is sent and the call throws `BlossomAuthUnavailableException`.

Without `auth`, reads stay anonymous and everything else authorises as a throwaway key.
The throwaway key comes from the `signerFactory` given to the constructor: without one, such an operation throws a `StateError` before sending anything.
Give `Blossom` an `authHandler` and it authorises as the logged account instead, only on the servers the handler agrees to.

## Files

`Files` uploads, downloads and deletes files with a simpler API than `Blossom`: it takes any url, and goes through Blossom only when the url names a blob.

```dart
final files = Files(blossom);

final blob = await files.download(
  url: 'https://cdn.example.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.pdf',
);

final json = await files.download(
  url: 'https://example.com/.well-known/nostr.json',
);

final results = await files.upload(
  file: BlossomFile(data: bytes, mimeType: 'image/png'),
);
```

A url naming a sha256, with or without a file extension (`https://cdn.example.com/<sha256>.pdf`), goes through Blossom.
Its own server is tried first, then `serverUrls`, then the server list of `pubkeyToFetchUserServerList`, which is read only once the others failed.
The bytes must hash to that sha256.
Any other url is fetched directly.

`upload`, `uploadFromFile` and `delete` use the logged account's server list (kind `10063`) when no `serverUrls` are given.

`checkUrl` answers the url itself when its server has the blob, extension included, and otherwise the url of a server that has it.

`upload` takes the same `strategy` as `Blossom.uploadBlob`.
A `BlossomFile` that already knows its `sha256` is not hashed again.
`uploadFromFile` and `downloadToFile` stream from and to disk, so a large file is never held whole in memory.
`uploadFromStream` uploads a file the app picked, on every platform, as `Blossom.uploadBlobFromStream` does.

Every method takes the same `auth` parameter as `Blossom`, see [Server authentication](#server-authentication-bud-01).
It is ignored for a plain url, which is fetched directly.

## Methods

### uploadBlob

Uploads a blob.
With `serverMediaOptimisation`, the `/media` endpoint is used (BUD-05), and the server's hash differs from the original.

With `UploadStrategy.mirrorAfterSuccess`, the other servers mirror the blob the first one answered with.
After a `/media` upload that blob has a new hash, so the mirrors sign their own `upload` authorization naming it (BUD-04): with a remote signer, that is a second prompt.

```dart
Future<List<BlobUploadResult>> uploadBlob({
  required Uint8List data,
  List<String>? serverUrls,
  String? contentType,
  UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
  bool serverMediaOptimisation = false,
  AuthPolicy? auth,
  String? pubkeyToFetchUserServerList,
  String? precomputedSha256,
  Future<void>? abortTrigger,
})
```

### uploadBlobFromFile

Reads the file in chunks, so a large file is never held whole in memory.
Native platforms only: a browser has no file paths, so there it fails with an `UnsupportedError`.
Upload a picked file with `uploadBlobFromStream` instead.

```dart
Stream<BlobUploadProgress> uploadBlobFromFile({
  required String filePath,
  List<String>? serverUrls,
  String? contentType,
  UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
  bool serverMediaOptimisation = false,
  AuthPolicy? auth,
  String? pubkeyToFetchUserServerList,
  String? precomputedSha256,
  Future<void>? abortTrigger,
})
```

### uploadBlobFromStream

Uploads the `contentLength` bytes `openRead` reads, on every platform, without holding them in memory.
It takes what a file picker gives, such as `PlatformFile.readAsByteStream` of `file_picker` or `XFile.openRead`:

```dart
final file = await FilePicker.pickFile();
final progress = blossom.uploadBlobFromStream(
  openRead: file!.readAsByteStream,
  contentLength: await file.length(),
);
```

`openRead` must read the same bytes from the start on every call: once to hash them, unless `precomputedSha256` is given, then once per server, and once more when a server asks the upload to authorise itself.
Hashing fails with an `ArgumentError` when it reads another length than `contentLength`.

```dart
Stream<BlobUploadProgress> uploadBlobFromStream({
  required Stream<List<int>> Function() openRead,
  required int contentLength,
  List<String>? serverUrls,
  String? contentType,
  UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
  bool serverMediaOptimisation = false,
  AuthPolicy? auth,
  String? pubkeyToFetchUserServerList,
  String? precomputedSha256,
  Future<void>? abortTrigger,
})
```

### checkUpload

Asks each server whether it would take the upload before any byte is sent (BUD-06).
Branch on `statusCode` (413 means too large) and show `reason` to the user.
BUD-06 is optional: a server without it answers something like 404, which says nothing about the upload.
A refused upload reports the same `statusCode` and `reason` in its `BlobUploadResult`.

```dart
Future<List<BlobUploadCheck>> checkUpload({
  required String sha256,
  required int contentLength,
  String? contentType,
  List<String>? serverUrls,
  bool serverMediaOptimisation = false,
  AuthPolicy? auth,
  String? pubkeyToFetchUserServerList,
  Future<void>? abortTrigger,
})
```

### getBlob

Downloads the blob, falling back to the next server when one does not have it or is offline.

```dart
Future<BlobResponse> getBlob({
  required String sha256,
  AuthPolicy? auth,
  List<String>? serverUrls,
  String? pubkeyToFetchUserServerList,
  Future<void>? abortTrigger,
})
```

### downloadBlobToFile

Writes the blob to a file without holding it in memory.
On the web it opens the browser's download dialog, `outputPath` naming the file.

```dart
Future<void> downloadBlobToFile({
  required String sha256,
  required String outputPath,
  AuthPolicy? auth,
  List<String>? serverUrls,
  String? pubkeyToFetchUserServerList,
  Future<void>? abortTrigger,
})
```

### checkBlob

Returns the url of a server that has the blob, without downloading it.
Useful for a video player that takes a url.

```dart
Future<String> checkBlob({
  required String sha256,
  AuthPolicy? auth,
  List<String>? serverUrls,
  String? pubkeyToFetchUserServerList,
  Future<void>? abortTrigger,
})
```

### getBlobStream

Like `getBlob`, but streams the data, which helps with large files such as videos.

```dart
Future<Stream<BlobResponse>> getBlobStream({
  required String sha256,
  AuthPolicy? auth,
  List<String>? serverUrls,
  String? pubkeyToFetchUserServerList,
  int chunkSize = 1024 * 1024,
  Future<void>? abortTrigger,
})
```

### listBlobs

```dart
Future<List<BlobDescriptor>> listBlobs({
  required String pubkey,
  List<String>? serverUrls,
  AuthPolicy? auth,
  DateTime? since,
  DateTime? until,
  Future<void>? abortTrigger,
})
```

### deleteBlob

```dart
Future<List<BlobDeleteResult>> deleteBlob({
  required String sha256,
  List<String>? serverUrls,
  AuthPolicy? auth,
  String? pubkeyToFetchUserServerList,
  Future<void>? abortTrigger,
})
```

### mirrorToServers

Copies a blob that already lives somewhere else onto other servers, without downloading it first.
`blossomUrl` may end with a file extension, such as `https://cdn.example.com/<sha256>.pdf`.

```dart
Future<List<BlobUploadResult>> mirrorToServers({
  required Uri blossomUrl,
  required List<String> targetServerUrls,
  AuthPolicy? auth,
  Future<void>? abortTrigger,
})
```

### directDownload

Downloads any url, without Blossom.
`directDownloadToFile` writes it to a file.

```dart
Future<BlobResponse> directDownload({
  required Uri url,
  Future<void>? abortTrigger,
})
```

### report

The report is a signed event in the request body, so `never()` signs it with a throwaway key rather than sending nothing.

```dart
Future<int> report({
  required String sha256,
  required String eventId,
  required String reportType,
  required String reportMsg,
  required String serverUrl,
  AuthPolicy? auth,
  Future<void>? abortTrigger,
})
```

## Publishing a server list

`BlossomUserServerList` publishes the logged account's server list, the most trusted server first.
It takes a `publish` that signs an event as the logged account and sends it to its author's write relays:

```dart
final publishes = RelayPublishes(relayManager: relayManager);

final serverList = BlossomUserServerList(
  publish: (event) async {
    final signed = await accounts.sign(event);
    final relayList = await nip65.fetch(signed.pubkey);
    return publishes
        .publish(
          signed,
          relays: relayList == null ? const [] : writeRelaysOf(relayList),
        )
        .done;
  },
  accounts: accounts,
);

await serverList.publishUserServerList(
  serverUrlsOrdered: ['https://blossom.example.com', 'https://cdn.example.com'],
);
```

`publishUserServerList` completes with whatever `publish` returns, here the answer of each relay.
Before signing anything, it throws a `FormatException` for a url that is not a server url, an `ArgumentError` for an empty list, and a `StateError` when nobody is logged in.

To read a user's server list, use `BlossomServersFetcher` and `blossomServersOf`, as in [Usage](#usage).
