# ndk_mock_relay

A [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) and [NIP-42](https://github.com/nostr-protocol/nips/blob/master/42.md) relay on a free local port, for the tests of the NDK packages. It depends on `ndk_core` only, and is not published.

```yaml
dev_dependencies:
  ndk_mock_relay: ^0.1.0
```

```dart
import 'package:ndk_mock_relay/ndk_mock_relay.dart';

final relay = MockRelay(requireAuthForRequests: true);
await relay.start();

// connect to relay.url, then look at what reached the relay
print(relay.received('REQ'));
print(relay.openClients.map((client) => client.authenticatedAs));

await relay.stop();
```

It stores the events it accepts, except ephemeral ones, and sends them to the subscriptions they match. Every socket gets its own AUTH challenge. It does not check signatures: that is the job of the client's `EventVerifier`.

The flags of `MockRelay` make it refuse or leave unanswered what a real relay may: REQs and EVENTs before AUTH, every EVENT, REQs past a number per socket (`maxSubscriptions`, like strfry), or AUTH, REQ and EVENT answers. `onEvent` and `onUnknown` let a test answer in place of the relay, and `publish` and `sendToAll` push from the relay side.

`ndk` keeps a larger mock relay of its own in `test/mocks`, with NIP-65 lists, NIP-46 and NIP-77, for its tests through `Ndk`.
