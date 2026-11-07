---
icon: file-zip
---

[!badge variant="primary" text="low level"]

[!badge text="CLI"](/guides/cli/blossom.md) — `ndk blossom upload|download|delete|list|mirror|check|servers`

## Setup

Blossom lives in the `ndk_blossom` package, which does not depend on `ndk`.

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_blossom: ^0.1.0
```

Build it on top of an NDK instance: it signs with its accounts, asks its
`NdkConfig.authHandler`, and reads server lists (kind `10063`) through
`ndk.blossomUserServerList`.

:::code source="../../packages/blossom/example/blossom_example_test.dart" language="dart" range="10-16" title="" :::

## Example

:::code source="../../packages/blossom/example/blossom_example_test.dart" language="dart" range="18-22" title="" :::

## When to use

For a simpler, more generic API, check out
[!ref](/usecases/files.md)

If no servers are specified the default user server list (kind `10063`) is used for upload and delete.

A read tries `serverUrls` first. Given `pubkeyToFetchUserServerList` too, it
reads that user's server list only once none of `serverUrls` had the blob, and
then tries the servers it did not try yet.

The auth events get automatically signed and are valid for five minutes
(`Blossom.defaultAuthExpiration`), or for the `authExpiration` passed to the
`Blossom` constructor. An operation that outlives it, such as a long streamed
download, signs a new event when a server refuses the expired one.

A server url may end with a slash, as kind `10063` lists often write it.

## Errors

A read that no server served (`getBlob`, `checkBlob`, `getBlobStream`,
`downloadBlobToFile`, `listBlobs`) throws a `BlossomRequestException`. Its
`errors` say why each server failed, in the order they were tried: an
`HttpRequestException` carries the status the server answered with.

```dart
try {
  await blossom.getBlob(sha256: hash, serverUrls: servers);
} on BlossomRequestException catch (e) {
  if (e.notFound) {
    // no server has the blob
  }
}
```

A download checks that the bytes hash to the sha256 it asked for. A server
that serves anything else fails with a `BlossomHashMismatchException`:
`getBlob` moves on to the next server, while `getBlobStream` ends with it and
`downloadBlobToFile` throws it without saving anything. A range read through
`BlossomRepository.getBlob` is not checked.

An operation with no server to talk to throws a `BlossomNoServerListException`
before sending anything: the user has no server list (kind `10063`), or an
empty one, or the call gave neither servers nor a pubkey. Its `pubkey` says
whose list is missing.

Writes report each server in their results instead: `BlobUploadResult` and
`BlobDeleteResult` say whether that server succeeded, and why not.

## Server authentication (BUD-01)

Some servers only serve a private blob, or only accept an upload, from a client
that signed a kind `24242` event. The `auth` parameter says which identity a
server may learn, as on
[requests](/usecases/requests.md#relay-authentication-nip-42) and
[broadcasts](/usecases/broadcast.md#relay-authentication-nip-42):

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

The account does not have to be one NDK knows. `allow` costs a refused HTTP
round trip, and for an upload a body sent twice, so prefer `require` when the
server is known to ask. If `require` names an account that cannot sign, nothing
is sent and the call throws `BlossomAuthUnavailableException`.

Without `auth`, reads stay anonymous and everything else authorises as a
throwaway key. With an [`AuthHandler`](/concepts/nip42-auth.md#authhandler), it authorises as the logged-in account
instead, and only reaches the servers the handler agrees to.

`useAuth` and `customSigner` were removed in favour of `auth`:

| removed | replace with |
| --- | --- |
| `useAuth: true` | `auth: AuthPolicy.require(account)`, with the logged-in account, or the one holding the `customSigner` passed alongside |
| `customSigner: s` alone | the same with the account holding `s`, except on a download or a check, where it never signed: drop it |
| `useAuth: false` | `auth: const AuthPolicy.never()` on `listBlobs`, nothing elsewhere |

### methods - Blossom

#### uploadBlob

upload a blob, if serverMediaOptimisation is set to `true` the `/media` endpoint is used.

With `UploadStrategy.mirrorAfterSuccess`, the other servers mirror the blob the
first one answered with. After a `/media` upload that blob has a new hash, so
the mirrors sign their own `upload` authorization naming it (BUD-04): with a
remote signer, that is a second prompt.

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

#### uploadBlobFromFile

Reads the file in chunks, so a large file is never held whole in memory.

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

#### checkUpload

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

#### getBlob

Download the blob and use fallback if the blob is not found or the server is offline.

```dart
Future<BlobResponse> getBlob({
  required String sha256,
  AuthPolicy? auth,
  List<String>? serverUrls,
  String? pubkeyToFetchUserServerList,
})
```

#### checkBlob

!!!
if you have a video player that uses a url you can use check to get a valid url first. Example can be found in NDK demo app
!!!

```dart
Future<String> checkBlob({
  required String sha256,
  AuthPolicy? auth,
  List<String>? serverUrls,
  String? pubkeyToFetchUserServerList,
})
```

#### getBlobStream

Similar to `getBlob`, it streams the data, which is helpful for video files.

```dart
Future<Stream<BlobResponse>> getBlobStream({
  required String sha256,
  AuthPolicy? auth,
  List<String>? serverUrls,
  String? pubkeyToFetchUserServerList,
  int chunkSize = 1024 * 1024,
})
```

#### listBlobs

```dart
Future<List<BlobDescriptor>> listBlobs({
  required String pubkey,
  List<String>? serverUrls,
  AuthPolicy? auth,
  DateTime? since,
  DateTime? until,
})
```

#### deleteBlob

```dart
Future<List<BlobDeleteResult>> deleteBlob({
  required String sha256,
  List<String>? serverUrls,
  AuthPolicy? auth,
  String? pubkeyToFetchUserServerList,
})
```

#### mirrorToServers

Copies a blob that already lives somewhere else onto other servers, without
downloading it first. `blossomUrl` may end with a file extension, such as
`https://cdn.example.com/<sha256>.pdf`.

```dart
Future<List<BlobUploadResult>> mirrorToServers({
  required Uri blossomUrl,
  required List<String> targetServerUrls,
  AuthPolicy? auth,
})
```

#### directDownload

```dart
Future<BlobResponse> directDownload({required Uri url})
```

#### report

The report is a signed event in the request body, so `never()` signs it with a
throwaway key rather than sending nothing.

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

### methods - BlossomUserServerList

To get and set the user server list e.g. on settings page, use `ndk.blossomUserServerList`. `BlossomUserServerList` lives in `ndk_blossom` too, and takes callbacks to query and publish, which `ndk` wires to its requests and broadcast

#### getUserServerList

:::code source="../../packages/blossom/lib/src/domain_layer/usecases/user_server_list/blossom_user_server_list.dart" language="dart" range="40-45" title="" :::

#### publishUserServerList

:::code source="../../packages/blossom/lib/src/domain_layer/usecases/user_server_list/blossom_user_server_list.dart" language="dart" range="69-73" title="" :::
