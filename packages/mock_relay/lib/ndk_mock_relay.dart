/// A NIP-01 and NIP-42 relay on a free local port, for the tests of the NDK
/// packages.
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
