# ndk_nip82

[NIP-82](https://github.com/nostr-protocol/nips/blob/master/82.md) software applications for [NDK](https://pub.dev/packages/ndk): discover the application (kind `32267`), release (kind `30063`) and asset (kind `3063`) events of a trusted publisher, and pick a compatible Android update among them.

It does not depend on `ndk`. It asks you how to query and subscribe to relays. `ndk_flutter` builds on it for its app update controller, widgets and verified APK installer.

## Install

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_nip82: ^0.1.0
```

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_nip82/ndk_nip82.dart';

final ndk = Ndk.defaultConfig();
final software = Software(
  query: (filter, {relays, timeout}) async {
    final response = ndk.requests.query(
      filter: filter,
      explicitRelays: relays,
      timeout: timeout,
    );
    final events = await response.future;
    return (
      events: events,
      anyRelayCompleted: response.relayOutcomes.values.any(
        (outcome) => outcome.status == RelayRequestStatus.eose,
      ),
    );
  },
  subscribe: (filter, {relays}) {
    final response = ndk.requests.subscription(
      filter: filter,
      explicitRelays: relays,
    );
    return (
      events: response.stream,
      close: () => ndk.requests.closeSubscription(response.requestId),
    );
  },
);

const app = SoftwareAppRef(
  publisher: '<trusted-publisher-hex-pubkey>',
  identifier: 'com.example.app',
);
const relays = ['wss://catalog.example'];

final metadata = await software.getApp(app: app, relays: relays);
final releases = await software.getReleases(app: app, relays: relays);
final assets = await software.resolveAssetsForReleases(releases, relays: relays);

final sub = software
    .watchReleases(app: app, relays: relays)
    .listen((releases) => print(releases.first.version));
await sub.cancel();
```

`query` answers `getApp`, `getReleases` and `resolveAssets*`, and `subscribe` answers `watchReleases`, which subscribes only once listened to and closes when cancelled. When `relays` is null or empty, the callbacks choose the relays. `anyRelayCompleted` tells an application or release that does not exist apart from relays that never finished answering: `getApp` and `getReleases` throw `SoftwareDiscoveryException` for the latter.

`selectUpdate` and `selectLatestCompatible` pick, from resolved assets, the Android APK that matches an `InstalledSoftware`: same package, compatible ABI and Android version, a matching signing certificate and, for `selectUpdate`, a newer version code.

More in [example/](example/) and the [software updates docs](https://dart-nostr.com/usecases/software/).
