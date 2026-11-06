---
icon: file-zip
---

[!badge variant="primary" text="high level"]

[!badge text="CLI"](/guides/cli/files.md) — `ndk files upload|download|delete|check`

## Setup

Files lives in the `ndk_blossom` package, which does not depend on `ndk`.

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_blossom: ^0.1.0
```

Files wraps a [Blossom](/usecases/blossom.md) client, built on top of an NDK
instance:

:::code source="../../packages/blossom/example/files_example_test.dart" language="dart" range="7-15" title="" :::

## Example

:::code source="../../packages/blossom/example/files_example_test.dart" language="dart" range="20-25" title="blossom" :::

:::code source="../../packages/blossom/example/files_example_test.dart" language="dart" range="38-40" title="non blossom url" :::

## How to use

Files uses blossom under the hood to get, upload and delete files. \
The default user server list, specified by kind `10063` is used for upload and delete

A url naming a sha256, with or without a file extension
(`https://cdn.example.com/<sha256>.pdf`), goes through blossom and falls back
on the other servers. Any other url is fetched directly.

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
await files.upload(
  file: myFile,
  auth: AuthPolicy.require(account),
);
```
