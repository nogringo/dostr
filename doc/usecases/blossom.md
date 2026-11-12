---
icon: file-zip
---

# Blossom

[`ndk_blossom`](https://pub.dev/packages/ndk_blossom) stores files on [Blossom](https://github.com/hzrd149/blossom) servers: upload, download, mirror, list and delete blobs, on the servers you pick or on a user's server list (kind `10063`). For a simpler API that also takes plain urls, see [Files](/usecases/files.md).

```yaml
dependencies:
  ndk_blossom: ^0.1.0
  ndk_accounts: ^0.1.0
  ndk_bip340: ^0.1.0
  ndk_core: ^0.11.0-dev.2
  ndk_fetchers: ^0.1.0
```

## Setup

`Blossom` signs as the logged account of an `AuthAccounts`, such as [Accounts](/usecases/accounts.md), and asks you how to read a user's server list. Here [fetchers](/usecases/fetchers.md) read it from the user's write relays:

```dart
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_blossom/ndk_blossom.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_fetchers/ndk_fetchers.dart';

final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relayManager,
  eventVerifier: Bip340EventVerifier(),
);
final nip65 = Nip65Fetcher(reqs: reqs);
final serverLists = BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65);

final accounts = Accounts(const Bip340EventSignerFactory());
final blossom = Blossom(
  accounts: accounts,
  eventSignerFactory: const Bip340EventSignerFactory(),
  getUserServerList: (pubkey) async {
    final serverList = await serverLists.fetch(pubkey);
    return serverList == null ? null : blossomServersOf(serverList);
  },
);
```

## Example

```dart
final blob = await blossom.getBlob(
  sha256: 'b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553',
  serverUrls: ['https://cdn.example.com', 'https://blossom.example.com'],
);
print('${blob.mimeType}, ${blob.data.length} bytes');
```

## Servers

Upload, list and delete use the user's server list (kind `10063`) when no `serverUrls` are given.

A read tries `serverUrls` first. Given `pubkeyToFetchUserServerList` too, it reads that user's server list only once none of `serverUrls` had the blob, and then tries the servers it did not try yet.

A server url may end with a slash, as kind `10063` lists often write it.

The authorization events are signed automatically and are valid for five minutes (`Blossom.defaultAuthExpiration`), or for the `authExpiration` passed to the `Blossom` constructor. An operation that outlives it, such as a long streamed download, signs a new event when a server refuses the expired one.

Cancelling the subscription to an upload stream, such as `uploadBlobFromFile`, aborts that upload. `blossom.abortPending()` ends every operation in flight with a `RequestAbortedException`, including one still waiting on a signer, and tries no other server.

## Errors

A read that no server served (`getBlob`, `checkBlob`, `getBlobStream`, `downloadBlobToFile`, `listBlobs`) throws a `BlossomRequestException`. Its `errors` say why each server failed, in the order they were tried: an `HttpRequestException` carries the status the server answered with.

```dart
try {
  await blossom.getBlob(sha256: hash, serverUrls: servers);
} on BlossomRequestException catch (e) {
  if (e.notFound) {
    // no server has the blob
  }
}
```

A download checks that the bytes hash to the sha256 it asked for. A server that serves anything else fails with a `BlossomHashMismatchException`: `getBlob` moves on to the next server, while `getBlobStream` ends with it and `downloadBlobToFile` throws it without saving anything.

An operation with no server to talk to throws a `BlossomNoServerListException` before sending anything: the user has no server list (kind `10063`), or an empty one, or the call gave neither servers nor a pubkey. Its `pubkey` says whose list is missing.

Writes report each server in their results instead: `BlobUploadResult` and `BlobDeleteResult` say whether that server succeeded, and why not.

## Server authentication (BUD-01)

Some servers only serve a private blob, or only accept an upload, from a client that signed a kind `24242` event. The `auth` parameter says which identity a server may learn, with the same `AuthPolicy` as relays use for [NIP-42](/concepts/nip42-auth.md):

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

The account does not have to be one of `accounts`. `allow` costs a refused HTTP round trip, and for an upload a body sent twice, so prefer `require` when the server is known to ask. If `require` names an account that cannot sign, nothing is sent and the call throws `BlossomAuthUnavailableException`.

Without `auth`, reads stay anonymous and everything else authorises as a throwaway key. Give `Blossom` an `authHandler` and it authorises as the logged account instead, only on the servers the handler agrees to.

## Methods

### uploadBlob

Uploads a blob. With `serverMediaOptimisation`, the `/media` endpoint is used (BUD-05), and the server's hash differs from the original.

With `UploadStrategy.mirrorAfterSuccess`, the other servers mirror the blob the first one answered with. After a `/media` upload that blob has a new hash, so the mirrors sign their own `upload` authorization naming it (BUD-04): with a remote signer, that is a second prompt.

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
})
```

### uploadBlobFromFile

Reads the file in chunks, so a large file is never held whole in memory. On the web it asks the user to pick a file.

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
})
```

### checkUpload

Asks each server whether it would take the upload before any byte is sent (BUD-06). Branch on `statusCode` (413 means too large) and show `reason` to the user. BUD-06 is optional: a server without it answers something like 404, which says nothing about the upload. A refused upload reports the same `statusCode` and `reason` in its `BlobUploadResult`.

```dart
Future<List<BlobUploadCheck>> checkUpload({
  required String sha256,
  required int contentLength,
  String? contentType,
  List<String>? serverUrls,
  bool serverMediaOptimisation = false,
  AuthPolicy? auth,
  String? pubkeyToFetchUserServerList,
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
})
```

### downloadBlobToFile

Writes the blob to a file without holding it in memory. On the web it opens the browser's download dialog.

```dart
Future<void> downloadBlobToFile({
  required String sha256,
  required String outputPath,
  AuthPolicy? auth,
  List<String>? serverUrls,
  String? pubkeyToFetchUserServerList,
})
```

### checkBlob

Returns the url of a server that has the blob, without downloading it. Useful for a video player that takes a url.

```dart
Future<String> checkBlob({
  required String sha256,
  AuthPolicy? auth,
  List<String>? serverUrls,
  String? pubkeyToFetchUserServerList,
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
})
```

### deleteBlob

```dart
Future<List<BlobDeleteResult>> deleteBlob({
  required String sha256,
  List<String>? serverUrls,
  AuthPolicy? auth,
  String? pubkeyToFetchUserServerList,
})
```

### mirrorToServers

Copies a blob that already lives somewhere else onto other servers, without downloading it first. `blossomUrl` may end with a file extension, such as `https://cdn.example.com/<sha256>.pdf`.

```dart
Future<List<BlobUploadResult>> mirrorToServers({
  required Uri blossomUrl,
  required List<String> targetServerUrls,
  AuthPolicy? auth,
})
```

### directDownload

Downloads any url, without Blossom. `directDownloadToFile` writes it to a file.

```dart
Future<BlobResponse> directDownload({required Uri url})
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
})
```

## Publishing a server list

`BlossomUserServerList` publishes the logged account's server list, the most trusted server first. It takes a `query` that returns the events of a kind by some authors, and a `publish` that signs an event and sends it to its author's write relays:

```dart
final publishes = RelayPublishes(relayManager: relayManager);

final serverList = BlossomUserServerList(
  query: ({required authors, required kind, required timeout}) async => [
    for (final event in (await serverLists.fetchAll(authors)).values)
      if (event != null) event,
  ],
  publish: (event) async {
    final signed = await accounts.sign(event);
    final relayList = await nip65.fetch(signed.pubKey);
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

`publishUserServerList` completes with whatever `publish` returns, here the answer of each relay. See [RelayPublishes](/usecases/relay-publishes.md).
