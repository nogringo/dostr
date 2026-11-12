This package helps you to easily produce Nostr apps by providing generics Widgets and functions.

## Features

- Nostr widgets
- Login persistence

## Getting started

### Add dependencies

```bash
flutter pub add ndk_core ndk_accounts ndk_flutter
```

### Add internationalization

Follow the [Official documentation](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization)

```dart
import 'package:ndk_flutter/l10n/app_localizations.dart' as ndk_flutter;

MaterialApp(
    localizationsDelegates: [
        ndk_flutter.AppLocalizations.delegate, // add this line
    ],
);
```

## Usage

```dart
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_flutter/ndk_flutter.dart';

final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final ndkFlutter = NdkFlutter(
  accounts: Accounts(const NdkEventSignerFactory()),
  relayReqs: RelayReqs(
    relayManager: relayManager,
    eventVerifier: NdkEventVerifier(),
  ),
  relayPublishes: RelayPublishes(relayManager: relayManager),
);

// reads saved accounts from secure storage and logs them in again
// typically called before runApp
await ndkFlutter.restoreAccountsState();

// call this every time the auth state changes
await ndkFlutter.saveAccountsState();

NBanner(ndkFlutter: ndkFlutter);
NPicture(ndkFlutter: ndkFlutter);
NName(ndkFlutter: ndkFlutter);
NUserProfile(ndkFlutter: ndkFlutter);
NLogin(ndkFlutter: ndkFlutter);
NSwitchAccount(ndkFlutter: ndkFlutter);
```

By default, the logged-in user is used for user widgets; you can override it by passing a `pubkey` parameter.

The widgets read profiles through `ndkFlutter.loadMetadata`, which asks the write relays of each pubkey with a `MetadataFetcher` of [`ndk_fetchers`](https://pub.dev/packages/ndk_fetchers). Pass your own `metadataFetcher` to share its cache and its `Nip65Fetcher` with the rest of the app.

## TODO

- [ ] NUserProfile optionnal show nsec and copy
- [ ] NUserProfile show the letter in the Picture and make it as big as possible

## Need more Widgets

Open an Issue
