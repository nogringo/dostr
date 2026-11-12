# Setup

## Install

```bash
dart pub add ndk_core ndk_bip340
# outbox model
dart pub add ndk_fetchers ndk_url_set
```

`ndk_core` has no signing or verification code: it takes any `EventVerifier`, and `ndk_bip340` gives a pure Dart one (`Bip340EventVerifier`). `RustEventVerifier` from `ndk_rust_verifier` is faster on native platforms but needs the Rust toolchain. On the web, `WebEventVerifier` from `ndk_web_crypto` is faster.

## Minimum init

```dart
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';

final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final reqs = RelayReqs(relayManager: relays, eventVerifier: Bip340EventVerifier());
final publishes = RelayPublishes(relayManager: relays);
```

Keep one `RelayManager` per app: it owns the connections.

## RelayManager options

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `nostrTransportFactory` | required | Opens the sockets. `WebSocketClientNostrTransportFactory(compressionEnabled: false)` saves memory on native |
| `accounts` | null | `AuthAccounts` (e.g. `Accounts` from `ndk_accounts`) a request without `auth` may authenticate as |
| `authHandler` | null | Asked before a pubkey is revealed to a relay (NIP-42). Without it, a request without `auth` stays anonymous |
| `allowReconnect` | true | Reconnect dropped connections with backoff |
| `reconnectMaximumStep` | 4 | Caps the doubling reconnect wait (4 → 4 s) |
| `anonymousIdleTimeout` | 1 min | Close an unused anonymous connection; null keeps it |
| `authenticatedIdleTimeout` | 5 min | Same for a connection bound to an identity |
| `subscriptionLimit` | null | `(url) => int?`, REQs per socket, e.g. NIP-11 `max_subscriptions`; 20 when unknown |
| `messageLengthLimit` | null | `(url) => int?`, max bytes per message, e.g. NIP-11 `max_message_length` |
| `onMessageLengthLearned` | null | Called when a relay closes with 1009; store it and answer `messageLengthLimit` after a restart |

NIP-11 documents come from `ndk_nip11` (`HttpRelayInfoRepo`, `CachedRelayInfoRepo`).

## Lifecycle

```dart
relays.relayConnectivityChanges.listen(print); // Stream<List<RelayConnectivity>>
await relays.reconnectClosedConnections();     // network back, app resumed
await relays.closeIdleConnections();           // app backgrounded
await relays.closeAllTransports();             // shutdown
```
