---
icon: file-zip
---

[!badge variant="primary" text="high level"]

[!badge text="CLI"](/guides/cli/files.md) — `ndk files upload|download|delete|check`

## Setup

NDK exposes Files as `ndk.files`, on top of [Blossom](/usecases/blossom.md) (`ndk.blossom`).

`Files` lives in the `ndk_blossom` package, which `ndk` depends on and re-exports. It does not depend on `ndk`: build `Files` from a `Blossom` client, see its [README](https://pub.dev/packages/ndk_blossom).

## Example

:::code source="../../packages/blossom/example/files_example_test.dart" language="dart" range="10-13" title="blossom" :::

:::code source="../../packages/blossom/example/files_example_test.dart" language="dart" range="25-27" title="non blossom url" :::

## How to use

Files uses blossom under the hood to get, upload and delete files. \
The default user server list, specified by kind `10063` is used for upload and delete

A url naming a sha256, with or without a file extension
(`https://cdn.example.com/<sha256>.pdf`), goes through blossom. Its own server
is tried first, then `serverUrls`, then the server list of `pubkey`, which is
read only once the others failed. The bytes must hash to that sha256. Any other
url is fetched directly.

`checkUrl` answers the url itself when its server has the blob, extension
included, and otherwise the url of a server that has it.

`upload` takes the same `strategy` as `Blossom.uploadBlob`. An `NdkFile` that
already knows its `sha256` is not hashed again.

If you need more granular control check out:
[!ref](/usecases/blossom.md)

## Server authentication

Every method takes an `auth` parameter saying which identity a blossom server
may learn, described in
[blossom](/usecases/blossom.md#server-authentication-bud-01). It is ignored for
a plain url, which is fetched directly.

```dart
await ndk.files.upload(
  file: myFile,
  auth: AuthPolicy.require(account),
);
```
