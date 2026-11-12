---
icon: info
order: 0
---

# Tips

## Keep one RelayManager

A `RelayManager` holds the relay connections, and every `RelayReqs`, `RelayPublishes` and fetcher built on it shares them. Create it once and pass it down, or provide it with [riverpod](https://pub.dev/packages/riverpod), get_it or a singleton:

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:riverpod/riverpod.dart';

final relayManagerProvider = Provider<RelayManager>((ref) {
  final relays = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  ref.onDispose(relays.closeAllTransports);
  return relays;
});

final relayReqsProvider = Provider<RelayReqs>(
  (ref) => RelayReqs(
    relayManager: ref.watch(relayManagerProvider),
    eventVerifier: Bip340EventVerifier(),
  ),
);
```

## Avoid layout shifts

Buffering events and updating the UI periodically avoids a redraw per event. With [rxdart](https://pub.dev/packages/rxdart):

```dart
import 'package:rxdart/rxdart.dart';

req.events
    .map((received) => received.event)
    .bufferTime(const Duration(milliseconds: 500))
    .where((events) => events.isNotEmpty)
    .listen((events) {
      // update the UI
    });
```

## Reduce native WebSocket memory overhead

Native applications can opt out of `permessage-deflate` negotiation:

```dart
final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(
    compressionEnabled: false,
  ),
);
```

Disabling compression can reduce memory and codec overhead for long-running services, but sends more bytes for compressible traffic and can perform worse on bandwidth-constrained links. Compression remains enabled by default.

Browser WebSocket APIs do not expose compression negotiation controls, so this setting has no effect on web builds.
