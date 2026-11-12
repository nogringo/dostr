/// A NIP-01, NIP-42 and NIP-77 relay on a local port, and a NIP-46 remote
/// signer behind it, for the tests of the NDK packages.
///
/// ```dart
/// final relay = MockRelay(requireAuthForRequests: true);
/// await relay.start();
/// // connect to relay.url
/// expect(relay.received('AUTH'), hasLength(1));
/// await relay.stop();
/// ```
library;

export 'src/mock_relay.dart';
export 'src/mock_remote_signer.dart';
