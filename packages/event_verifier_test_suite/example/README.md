# Example

Add the suite as a dev dependency:

```yaml
dev_dependencies:
  dostr_event_verifier_test_suite: ^0.1.0
```

## A BIP-340 verifier

A verifier with no signer of its own signs with `Bip340SignerFactory`, so it also adds [`dostr_bip340`](https://pub.dev/packages/dostr_bip340) as a dev dependency:

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_event_verifier_test_suite/dostr_event_verifier_test_suite.dart';
import 'package:my_verifier/my_verifier.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'MyEventVerifier',
    createVerifier: MyEventVerifier.new,
    createSigner: const Bip340SignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
```

## A verifier with its own signer

A package that ships both a signer and a verifier, such as `dostr_web_crypto`, signs with its own signer.
The two could share a serialization bug and still agree: the events of `bip340ExternalEvents`, which other clients signed, catch it.

```dart
import 'package:dostr_event_verifier_test_suite/dostr_event_verifier_test_suite.dart';
import 'package:my_crypto/my_crypto.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'MyEventVerifier',
    createVerifier: MyEventVerifier.new,
    createSigner: const MySignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
```
