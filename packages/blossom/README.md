# ndk_blossom

[Blossom](https://github.com/hzrd149/blossom) file storage for [NDK](https://pub.dev/packages/ndk): upload, download, mirror and delete blobs, and manage a user's server list (kind `10063`).

## Install

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_blossom: ^0.1.0
```

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_blossom/ndk_blossom.dart';

final ndk = Ndk.defaultConfig();

// high level: a Blossom url goes through Blossom, any other url is fetched directly
final files = Files(ndk);
final blob = await files.download(
  url: 'https://cdn.hzrd149.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.pdf',
);

// low level: every BUD operation, with the servers you choose
final blossom = Blossom(ndk);
final blobs = await blossom.listBlobs(pubkey: pubkey);

// the user's server list
final serverList = BlossomUserServerList(ndk);
final servers = await serverList.getUserServerList(pubkeys: [pubkey]);
```

`Blossom(ndk)` signs with the accounts of that NDK instance and asks its `NdkConfig.authHandler` before revealing an identity to a server. Each operation takes an `auth` policy, see the [Blossom docs](https://dart-nostr.com/usecases/blossom/).

More in [example/](example/).
