---
icon: upload
---

[!badge variant="primary" text="low level"]

Publishes a signed event to relays you pick (NIP-01 EVENT), with nothing on
top: no signing, no cache, no outbox routing, no retry. [Broadcast](broadcast.md)
adds all of that on the same network path.

## Usage

```dart
final signed = await signer.sign(event);

final responses = await ndk.relayPublishes
    .publish(
      signed,
      relays: ['wss://relay.example.com', 'wss://other.example.com'],
      timeout: Duration(seconds: 5),
    )
    .broadcastDoneFuture;

for (final response in responses) {
  print('${response.relayUrl}: ${response.broadcastSuccessful} ${response.msg}');
}
```

## What you get

- Each relay gets the event once, whatever the list holds twice.
- A relay that cannot be reached is reported as failed, with the reason in
  `msg`, instead of waiting for the timeout.
- The response is done once every relay answered, once `considerDonePercent`
  of them accepted the event, or after `timeout`.
- `auth` takes the same `AuthPolicy` as [Requests](requests.md): a relay that
  answers `auth-required` gets the event again on a connection bound to the
  account it allows.
- An unsigned event is refused with an `ArgumentError`.

[RelayReqs](relay-reqs.md) is the reading counterpart.
