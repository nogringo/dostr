# ndk_mock_relay

A [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md), [NIP-42](https://github.com/nostr-protocol/nips/blob/master/42.md) and [NIP-77](https://github.com/nostr-protocol/nips/blob/master/77.md) relay on a local port, with a [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) remote signer behind it, for the tests of the NDK packages. It is not published.

```yaml
dev_dependencies:
  ndk_mock_relay: ^0.1.0
```

```dart
import 'package:ndk_mock_relay/ndk_mock_relay.dart';

final relay = MockRelay(requireAuthForRequests: true);
await relay.start(events: [note]);

// connect to relay.url, then look at what reached the relay
print(relay.received('REQ'));
print(relay.connectionsAuthenticatedAs(pubkey));

await relay.stop();
```

It stores the events it accepts by the NIP-01 rules: ephemeral ones are only delivered, and a replaceable or addressable event replaces the older version. A kind 5 deletes the events of its author, and the gift wraps addressed to it (NIP-59). Every socket gets its own AUTH challenge. It does not check signatures: that is the job of the client's `EventVerifier`.

`url` is known before `start`, and stays the same across a `stop` and a new `start`, so a test can point a client at a relay that is not up yet or restart it. Pass `port` to pick it.

The flags of `MockRelay` make it refuse or leave unanswered what a real relay may: REQs, EVENTs and NEG-OPENs before AUTH, with or without a challenge, EVENTs (all of them or the first few), REQs past a number per socket (`maxSubscriptions`, like strfry), messages past a number of bytes (`maxMessageLength`, by closing the socket with a 1009), both of which its NIP-11 document publishes, or AUTH, REQ and EVENT answers. `start` can also hold every message or handshake for a while. `onConnect`, `onMessage` and `onEvent` let a test answer in place of the relay, and `publish` and `sendToAll` push from the relay side.

`MockRemoteSigner` answers the NIP-46 requests that reach the relays it is given, with a fixed key.
