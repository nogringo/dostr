---
icon: cpu
label: Proof of work (NIP-13)
---

# Proof of work (NIP-13)

[`dostr_nip13`](https://pub.dev/packages/dostr_nip13) mines an event until its id starts with enough zero bits, reads the difficulty of an id, and checks an event against the target its `nonce` tag commits to ([NIP-13](https://github.com/nostr-protocol/nips/blob/master/13.md)).

```yaml
dependencies:
  dostr_nip13: ^0.1.0
  dostr_core: ^0.11.0-dev.2
  dostr_bip340: ^0.1.0
```

## Mining

:::code source="../../packages/nip13/example/dostr_nip13_example.dart" language="dart" range="5-14" title="" :::

`mineEvent` returns an unsigned copy of the event with a `["nonce", "<nonce>", "<target>"]` tag, replacing any existing one. The id covers the pubkey and `created_at`, so set both before mining and change neither after.

- Mining runs in its own isolate. On the web it runs on the main thread and blocks the UI.
- Each try picks a random nonce, so a difficulty `d` takes 2^d tries on average: about a million at 20. `mineEvent` throws an `Exception` after `maxIterations` tries, 1,000,000 by default, so raise it for 20 and above.

## Publishing

Mine an event that has the signer's pubkey, sign it, then publish it with [RelayPublishes](/usecases/relay-publishes.md):

```dart
final event = Nip01Event(
  pubKey: signer.getPublicKey(),
  kind: 1,
  content: 'hello nostr',
);
final mined = await Nip13.mineEvent(event, 20, maxIterations: 10000000);
final signed = await signer.sign(mined);

await RelayPublishes(relayManager: relays)
    .publish(signed, relays: ['wss://relay.example.com'])
    .done;
```

`signer` is any `EventSigner`, for example a `Bip340EventSigner`, and `relays` is the app's `RelayManager`, see [Relay REQs](/usecases/relay-reqs.md#setup).

## Checking

- `Nip13.getDifficulty(id)` counts the leading zero bits of an id, and `Nip13.checkDifficulty(id, target)` compares them with a target.
- `Nip13.validateEvent(event)` checks the event against the target of its `nonce` tag (`getTargetDifficultyFromEvent`), and returns true when it has none. To require work from others, check the id against your own minimum with `checkDifficulty`.
- `Nip13.calculateCommitment(id)` is the work behind an id, 2^difficulty, as a `BigInt`.
- They read the id as it is and do not recompute it. For an event you did not build, check `event.hasValidId` first, or verify the event.
