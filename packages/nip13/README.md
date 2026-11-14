# dostr_nip13

[NIP-13](https://github.com/nostr-protocol/nips/blob/master/13.md) proof of work for Nostr events: mine an event until its id has enough leading zero bits, read the difficulty of an id, and check an event against the target its `nonce` tag commits to.

Mining runs in its own isolate (on the main thread on the web).

## Install

```yaml
dependencies:
  dostr_nip13: ^0.1.0
  dostr_core: ^0.1.0 # only to publish, as below
```

## Usage

```dart
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip13/dostr_nip13.dart';

final event = Nip01Event(
  pubKey: signer.getPublicKey(),
  kind: 1,
  content: 'hello nostr',
);
final mined = await Nip13.mineEvent(event, 20, maxIterations: 10000000);
Nip13.getDifficulty(mined.id); // >= 20
Nip13.validateEvent(mined); // true

final signed = await signer.sign(mined);
await RelayPublishes(relayManager: relays)
    .publish(signed, relays: ['wss://relay.example.com'])
    .done;
```

`mineEvent` adds a `["nonce", "<nonce>", "<target>"]` tag (replacing any existing one) and returns an unsigned event, since the id changes with the nonce. Sign it after mining with an `EventSigner` (`signer`, for example a `Bip340EventSigner` of `dostr_bip340`), then publish it with `RelayPublishes` of `dostr_core`, where `relays` is the app's `RelayManager`. The id covers the pubkey and `created_at`, so set both before mining, to the signer's pubkey, and change neither after.

Each try picks a random nonce, so a difficulty `d` takes 2^d tries on average, about a million at 20. `mineEvent` throws an `Exception` after `maxIterations` tries, 1,000,000 by default, so raise it for 20 and above.

## Checking

- `Nip13.getDifficulty(id)` counts the leading zero bits of an id, and `Nip13.checkDifficulty(id, target)` compares them with a target.
- `Nip13.validateEvent(event)` checks the event against the target of its `nonce` tag (`getTargetDifficultyFromEvent`), and returns true when it has none. To require work from others, check the id against your own minimum with `checkDifficulty`.
- `Nip13.calculateCommitment(id)` is the work behind an id, 2^difficulty, as a `BigInt`.
- They read the id as it is and do not recompute it. For an event you did not build, check `event.hasValidId` first, or verify the event.

## Coming from `ndk`

`ndk.proofOfWork` and the `ProofOfWork` usecase have no counterpart here. Use the static methods of `Nip13`:

| Before | After |
| ------ | ----- |
| `ndk.proofOfWork.minePoW(event: e, targetDifficulty: d)` | `Nip13.mineEvent(e, d)` |
| `ndk.proofOfWork.getPoWDifficulty(e)` | `Nip13.getDifficulty(e.id)` |
| `ndk.proofOfWork.checkPoWDifficulty(event: e, targetDifficulty: d)` | `Nip13.checkDifficulty(e.id, d)` |
| `ndk.proofOfWork.getTargetDifficultyFromEvent(e)` | `Nip13.getTargetDifficultyFromEvent(e)` |
| `ndk.proofOfWork.powCommitment(e)` | `Nip13.calculateCommitment(e.id)`, now a `BigInt` |

`package:ndk/shared/nips/nip13/nip13.dart` is now `package:dostr_nip13/dostr_nip13.dart`.
