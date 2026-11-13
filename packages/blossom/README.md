# dostr_blossom

[Blossom](https://github.com/hzrd149/blossom) file storage for Nostr: upload, download, mirror and delete blobs on a user's servers (kind `10063`).

It signs through [`dostr_signer`](https://pub.dev/packages/dostr_signer), which also gives it its accounts and auth policies, and asks you how to read a user's server list.

## Install

```yaml
dependencies:
  dostr_blossom: ^0.1.0
  dostr_accounts: ^0.1.0
  dostr_bip340: ^0.1.0
  dostr_core: ^0.11.0-dev.2
  dostr_fetchers: ^0.1.0
```

## Usage

```dart
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_blossom/dostr_blossom.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';

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

// high level: a Blossom url goes through Blossom, any other url is fetched directly
final files = Files(blossom);
final blob = await files.download(
  url: 'https://cdn.hzrd149.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.pdf',
);

// low level: every BUD operation, with the servers you choose
final blobs = await blossom.listBlobs(pubkey: pubkey);
```

`Blossom` signs with the logged-in account of `accounts` and asks an `authHandler`, when given one, before revealing an identity to a server. Each operation takes an `auth` policy, see the [Blossom docs](https://nogringo.github.io/dostr/usecases/blossom/).

To read or publish a user's server list, build a `BlossomUserServerList` with a `query` that returns the events of a kind by some authors, and a `publish` that signs an event as the logged account and sends it to its author's outbox relays. `publishUserServerList` completes with whatever `publish` returns:

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

Cancelling the subscription to an upload stream, such as `uploadBlobFromFile`, aborts that upload. `blossom.abortPending()` ends every operation in flight with a `RequestAbortedException`, including one still waiting on a signer, and tries no other server.

More in [example/](example/).
