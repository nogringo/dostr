# ndk_nip11

[NIP-11](https://github.com/nostr-protocol/nips/blob/master/11.md) relay information for [NDK](https://pub.dev/packages/ndk): fetch the document a relay serves about itself (name, software, supported NIPs, limitations, fees), cache it, and follow the connectivity of the relays NDK talks to. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes `Connectivy` as `ndk.connectivity`:

```dart
import 'package:ndk/ndk.dart';

final info = await ndk.connectivity.getRelayInfo('wss://relay.example.com');
print('search? ${info?.supportsNip('50') ?? false}');

ndk.connectivity.relayConnectivityChanges.listen(print);
await ndk.connectivity.tryReconnect();
```

## Standalone

```yaml
dependencies:
  ndk_nip11: ^0.1.0
  ndk_core: ^0.11.0-dev.2
  ndk_http: ^0.1.0
  http: ^1.6.0
```

```dart
import 'package:http/http.dart' as http;
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_nip11/ndk_nip11.dart';

final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final connectivity = Connectivy(
  relayManager,
  RelayInfoHttpRepoImpl(httpDS: NdkHttp(http.Client())),
);

final info = await connectivity.getRelayInfo('wss://relay.example.com');
print(info?.limitation?.maxSubscriptions);
```

`getRelayInfo` fetches the document over HTTP(S) on the relay's own url, once per relay: concurrent calls share the request, and a failed fetch is retried on the next call. It returns null when the relay serves no document. `RelayInfoHttpRepoImpl` alone fetches without caching.

More in [example/](example/) and the [connectivity docs](https://dart-nostr.com/usecases/connectivity/).

## Coming from `ndk`

`Connectivy`, `RelayInfo`, `RelayLimitation`, `RelayFees`, `RelayFee`, `RelayInfoRepo` and `RelayInfoHttpRepoImpl` keep their names, and `package:ndk/ndk.dart` now exports them all. The deep imports under `package:ndk/` (`domain_layer/entities/relay_info.dart`, `domain_layer/repositories/relay_info_repo.dart`, `data_layer/repositories/relay_info_http_impl.dart` and `domain_layer/usecases/connectivity/connectivity.dart`) are now `package:ndk_nip11/ndk_nip11.dart`.
