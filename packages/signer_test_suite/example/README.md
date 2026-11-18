# Example

Add the suite and [`dostr_bip340`](https://pub.dev/packages/dostr_bip340) as dev dependencies:

```yaml
dev_dependencies:
  dostr_bip340: ^0.1.0
  dostr_signer_test_suite: ^0.1.0
```

## A local signer

A signer that holds its key runs `runLocalSignerFactoryTestSuite` against its `LocalSignerFactory`.
Peers of `Bip340SignerFactory` check that it encrypts like the reference implementation:

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';
import 'package:my_signer/my_signer.dart';

void main() {
  runLocalSignerFactoryTestSuite(
    name: 'MySignerFactory',
    factory: const MySignerFactory(),
    verifier: Bip340EventVerifier(),
    createPeer: const Bip340SignerFactory().createWithNewKeyPair,
  );
}
```

## A signer that waits for the user

A remote or extension signer runs `runSignerTestSuite` with `interactive: true`, so the suite also checks its pending requests and their cancellation:

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';
import 'package:my_signer/my_signer.dart';

void main() {
  runSignerTestSuite(
    name: 'MyRemoteSigner',
    createSigner: () => MyRemoteSigner.connect(...),
    createPeer: const Bip340SignerFactory().createWithNewKeyPair,
    verifier: Bip340EventVerifier(),
    interactive: true,
  );
}
```
