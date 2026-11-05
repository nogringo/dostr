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

final outcomes = await ndk.relayPublishes
    .publish(
      signed,
      relays: ['wss://relay.example.com', 'wss://other.example.com'],
      timeout: Duration(seconds: 5),
    )
    .done;

for (final response in outcomes.values) {
  print('${response.relayUrl}: ${response.broadcastSuccessful} ${response.msg}');
}
```

## What you get

- Each relay gets the event once, whatever the list holds twice.
- A relay that cannot be reached is reported as failed, with the reason in
  `msg`, instead of waiting for the timeout.
- `done` completes once every relay answered, once `considerDonePercent` of
  them accepted the event, or after `timeout`. `outcomes` and `outcomesStream`
  show the answers as they come, keyed by relay url like those of
  [RelayReqs](relay-reqs.md).
- `auth` takes the same `AuthPolicy` as [Requests](requests.md): a relay that
  answers `auth-required` gets the event again on a connection bound to the
  account it allows.
- An unsigned event is refused with an `ArgumentError`.

[RelayReqs](relay-reqs.md) is the reading counterpart.
