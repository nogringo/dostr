# dostr_event_verifier_test_suite

A shared test suite for implementations of the `EventVerifier` of [`dostr_nip01`](https://pub.dev/packages/dostr_nip01). Every verifier runs the same cases, so they cannot drift apart on what they accept.

It is not published: the verifiers of this workspace (`dostr_bip340`, `dostr_rust_verifier`, `dostr_web_crypto`) use it.

## Usage

Add `dostr_event_verifier_test_suite` as a **dev dependency** of a workspace package:

```yaml
dev_dependencies:
  dostr_event_verifier_test_suite: ^0.1.0
```

Then in your test file:

```dart
import 'package:dostr_event_verifier_test_suite/dostr_event_verifier_test_suite.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'MyEventVerifier',
    createVerifier: MyEventVerifier.new,
    createSigner: () => MyEventSigner.withNewKey(),
  );
}
```

`createSigner` must return a signer with a fresh key on each call, using the signature scheme the verifier checks. That is how a non-BIP-340 verifier, such as ML-DSA, runs the same suite.

A BIP-340 verifier also passes `externalEvents: bip340ExternalEvents`. The suite signs its own events, so a signer and a verifier sharing a serialization bug would still agree: these events, signed by other clients, catch it.

## What's tested

| Group | What it verifies |
|-------|-----------------|
| **Accepts an event signed by another implementation** | Each of `externalEvents` |
| **Accepts a signed event** | Empty content and tags, empty tag values, quotes, unicode, every control character (NUL included) in content and tags, kinds 0 and 65535, a large event |
| **Rejects an event changed after signing** | Content, tag values (NUL suffixes included), tags added or removed, kind and created_at shifted (by 1, 65536, 2^32), another pubkey, a flipped sig bit |
| **Rejects an event whose** | sig is missing; sig, id or pubkey is empty, cut in half, one byte short or long, of odd length, or not hex; sig, id or pubkey is not lowercase, or has a `+` sign. The verifier must return `false`, never throw |
