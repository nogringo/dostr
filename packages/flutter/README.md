This package helps you to easily produce Nostr apps by providing generics Widgets and functions.

## Features

- Nostr widgets
- Login persistence

## Getting started

### Add dependencies

```bash
flutter pub add dostr_core dostr_accounts dostr_flutter
```

### Add internationalization

Follow the [Official documentation](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization)

```dart
import 'package:dostr_flutter/l10n/app_localizations.dart' as dostr_flutter;

MaterialApp(
    localizationsDelegates: dostr_flutter.AppLocalizations.localizationsDelegates,
    supportedLocales: dostr_flutter.AppLocalizations.supportedLocales,
);
```

`localizationsDelegates` holds the widgets' delegate along with Flutter's Material, Cupertino and widgets delegates. If your app has its own localizations, add `dostr_flutter.AppLocalizations.delegate` to your list instead.

## Usage

```dart
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_flutter/dostr_flutter.dart';

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

// NLogin, NSwitchAccount and NUserProfile call it themselves:
// call it only after changing accounts from your own code
await ndkFlutter.saveAccountsState();

NBanner(ndkFlutter: ndkFlutter);
NPicture(ndkFlutter: ndkFlutter);
NName(ndkFlutter: ndkFlutter);
NUserProfile(ndkFlutter: ndkFlutter);
NLogin(ndkFlutter: ndkFlutter);
NSwitchAccount(ndkFlutter: ndkFlutter);
```

By default, the logged-in user is used for user widgets; you can override it by passing a `pubkey` parameter.

The widgets read profiles through `ndkFlutter.loadMetadata`, which asks the write relays of each pubkey with a `MetadataFetcher` of [`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers). Pass your own `metadataFetcher` to share its cache and its `Nip65Fetcher` with the rest of the app.

## TODO

- [ ] NUserProfile optionnal show nsec and copy
- [ ] NUserProfile show the letter in the Picture and make it as big as possible

## Need more Widgets

Open an Issue
