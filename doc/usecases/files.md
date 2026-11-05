---
icon: file-zip
---

[!badge variant="primary" text="high level"]

[!badge text="CLI"](/guides/cli/files.md) — `ndk files upload|download|delete|check`

## Setup

Files lives in the `ndk_blossom` package.

```yaml
dependencies:
  ndk_blossom: ^0.1.0
```

## Example

:::code source="../../packages/blossom/example/files_example_test.dart" language="dart" range="10-15" title="blossom" :::

:::code source="../../packages/blossom/example/files_example_test.dart" language="dart" range="28-30" title="non blossom url" :::

## How to use

Files uses blossom under the hood to get, upload and delete files. \
The default user server list, specified by kind `10063` is used for upload and delete

If you need more granular control check out:
[!ref](/usecases/blossom.md)

## Server authentication

Every method takes an `auth` parameter saying which identity a blossom server
may learn, described in
[blossom](/usecases/blossom.md#server-authentication-bud-01). It is ignored for
a plain url, which is fetched directly.

```dart
await Files(ndk).upload(
  file: myFile,
  auth: AuthPolicy.require(account),
);
```
