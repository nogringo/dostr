---
icon: file-zip
---

# Files

`Files`, from [`dostr_blossom`](https://pub.dev/packages/dostr_blossom), uploads, downloads and deletes files with a simpler API than [Blossom](/usecases/blossom.md): it takes any url, and goes through Blossom only when the url names a blob.

```yaml
dependencies:
  dostr_blossom: ^0.1.0
```

## Example

Build it from a `Blossom` client, set up as in [Blossom](/usecases/blossom.md#setup):

```dart blossom url
final files = Files(blossom);

final blob = await files.download(
  url: 'https://cdn.example.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.pdf',
);
print('${blob.mimeType}, ${blob.data.length} bytes');
```

```dart plain url
final json = await files.download(
  url: 'https://example.com/.well-known/nostr.json',
);
```

```dart upload
final results = await files.upload(
  file: NdkFile(data: bytes, mimeType: 'image/png'),
);
```

## How it works

A url naming a sha256, with or without a file extension (`https://cdn.example.com/<sha256>.pdf`), goes through Blossom. Its own server is tried first, then `serverUrls`, then the server list of `pubkey`, which is read only once the others failed. The bytes must hash to that sha256. Any other url is fetched directly.

`upload`, `uploadFromFile` and `delete` use the logged account's server list (kind `10063`) when no `serverUrls` are given.

`checkUrl` answers the url itself when its server has the blob, extension included, and otherwise the url of a server that has it.

`upload` takes the same `strategy` as `Blossom.uploadBlob`. An `NdkFile` that already knows its `sha256` is not hashed again. `uploadFromFile` and `downloadToFile` stream from and to disk, so a large file is never held whole in memory.

## Server authentication

Every method takes an `auth` parameter saying which identity a Blossom server may learn, described in [Blossom](/usecases/blossom.md#server-authentication-bud-01). It is ignored for a plain url, which is fetched directly.

```dart
await files.upload(
  file: myFile,
  auth: AuthPolicy.require(account),
);
```
