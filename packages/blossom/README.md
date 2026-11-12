# dostr_blossom

[Blossom](https://github.com/hzrd149/blossom) file storage for [NDK](https://pub.dev/packages/ndk): upload, download, mirror and delete blobs on a user's servers (kind `10063`).

It does not depend on `ndk`. It signs through [`dostr_signer`](https://pub.dev/packages/dostr_signer), which also gives it its accounts and auth policies, and asks you how to read a user's server list. NDK exposes it, wired to its accounts and server lists, as `ndk.blossom` and `ndk.files`: build it yourself, as below, only to wire it differently.

## Install

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  dostr_blossom: ^0.1.0
```

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:dostr_blossom/dostr_blossom.dart';

final ndk = Ndk.defaultConfig();

final blossom = Blossom(
  accounts: ndk.accounts,
  eventSignerFactory: ndk.config.eventSignerFactory,
  authHandler: ndk.config.authHandler,
  getUserServerList: (pubkey) =>
      ndk.blossomUserServerList.getUserServerList(pubkeys: [pubkey]),
);

// high level: a Blossom url goes through Blossom, any other url is fetched directly
final files = Files(blossom);
final blob = await files.download(
  url: 'https://cdn.hzrd149.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.pdf',
);

// low level: every BUD operation, with the servers you choose
final blobs = await blossom.listBlobs(pubkey: pubkey);
```

`Blossom` signs with the logged-in account of `accounts` and asks `authHandler` before revealing an identity to a server. Each operation takes an `auth` policy, see the [Blossom docs](https://dart-nostr.com/usecases/blossom/).

To read or publish a user's server list, use `ndk.blossomUserServerList`. Without `ndk`, build a `BlossomUserServerList` with a `query` that returns the events of a kind by some authors, and a `publish` that signs an event as the logged account and sends it to its author's outbox relays. `publishUserServerList` completes with whatever `publish` returns:

```dart
final serverList = BlossomUserServerList(
  query: ({required authors, required kind, required timeout}) =>
      myRelays.query(authors: authors, kinds: [kind], timeout: timeout),
  publish: (event) async =>
      myRelays.publish(await accounts.sign(event)),
  accounts: accounts,
);
final servers = await serverList.getUserServerList(pubkeys: [pubkey]);
```

Cancelling the subscription to an upload stream, such as `uploadBlobFromFile`, aborts that upload. `blossom.abortPending()` ends every operation in flight with a `RequestAbortedException`, including one still waiting on a signer, and tries no other server. `Blossom` does not follow the `Ndk` lifecycle on its own, so tie it to whatever owns it:

```dart
ndk.addLifecycleHooks(onDestroy: () async => blossom.abortPending());
```

More in [example/](example/).
