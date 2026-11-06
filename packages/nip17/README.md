# ndk_nip17

[NIP-17](https://github.com/nostr-protocol/nips/blob/master/17.md) private direct messages for [NDK](https://pub.dev/packages/ndk): gift-wrapped text (kind `14`) and encrypted file (kind `15`) messages, conversations grouped by peer, and the DM relay list (kind `10050`).

## Install

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_nip17: ^0.1.0
```

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_nip17/ndk_nip17.dart';

final ndk = Ndk.defaultConfig();
final dms = Dms(ndk);

// where the logged-in account receives its DMs
await dms.publishDmRelays(relayUrlsOrdered: ['wss://inbox.example.com']);

await dms.sendMessage(recipientPubKey: pubkey, content: 'hello');

final conversations = await dms.loadConversations();
final cached = await dms.loadConversationsSnapshot();
```

`Dms(ndk)` signs and decrypts with the logged-in account of that NDK instance, reads DM relay lists through `ndk.userRelayLists`, and reuses its cache of decrypted gift wraps. Sending fails when the sender or the recipient has no DM relay list.

More in [example/](example/) and the [DM docs](https://dart-nostr.com/usecases/dms/).
