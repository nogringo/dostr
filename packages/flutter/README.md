# dostr_flutter

Ready-made Nostr widgets for Flutter apps (login, profiles, account switcher, pending signer requests), and logged in accounts kept across restarts.

It re-exports [`dostr_nip07`](https://pub.dev/packages/dostr_nip07), [`dostr_nip55`](https://pub.dev/packages/dostr_nip55) and [`dostr_web_crypto`](https://pub.dev/packages/dostr_web_crypto).

## Install

```bash
flutter pub add dostr_core dostr_accounts dostr_flutter material_ui
```

The widgets are built on [`material_ui`](https://pub.dev/packages/material_ui), so your app must use it too. Its `Theme` and `Material` are separate from those of `package:flutter/material.dart`: inside a `MaterialApp` from the latter, the widgets ignore your theme and fail their `Material` checks. See the [migration steps](https://pub.dev/packages/material_ui#migrating-existing-code-to-this-package).

## Usage

```dart
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_flutter/l10n/app_localizations.dart' as dostr_flutter;
import 'package:material_ui/material_ui.dart';

final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);

final dostrFlutter = DostrFlutter(
  accounts: Accounts(const DostrEventSignerFactory()),
  relayReqs: RelayReqs(
    relayManager: relayManager,
    eventVerifier: DostrEventVerifier(),
  ),
  relayPublishes: RelayPublishes(relayManager: relayManager),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dostrFlutter.restoreAccountsState();

  runApp(
    MaterialApp(
      localizationsDelegates: const [
        dostr_flutter.AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: dostr_flutter.AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StreamBuilder(
          stream: dostrFlutter.accounts.authStateChanges,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (dostrFlutter.accounts.isLoggedIn)
                NUserProfile(dostrFlutter: dostrFlutter)
              else
                NLogin(dostrFlutter: dostrFlutter),
            ],
          ),
        ),
      ),
    ),
  );
}
```

`DostrEventSignerFactory` and `DostrEventVerifier` pick an implementation per platform. On the web they are `WebEventSignerFactory` and `WebEventVerifier` from `dostr_web_crypto`. Elsewhere they are `Bip340EventSignerFactory` and `RustEventVerifier` from [`dostr_rust_verifier`](https://pub.dev/packages/dostr_rust_verifier), whose build hook compiles Rust: install the [Rust toolchain](https://rustup.rs) to build for Android, iOS or desktop.

`DostrFlutter` also holds `bunkers`, the `Bunkers` of [`dostr_nip46`](https://pub.dev/packages/dostr_nip46), and a `metadataFetcher`. The widgets read profiles through `dostrFlutter.loadMetadata`, which asks the write relays of each pubkey with a `MetadataFetcher` of [`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers). Pass your own `metadataFetcher` to share its cache and its `Nip65Fetcher` with the rest of the app.

To answer NIP-42 authentication, give the same `Accounts` to the `RelayManager`, see the relay authentication of [`dostr_accounts`](https://pub.dev/packages/dostr_accounts#relay-authentication).

## Localization

The widgets read their texts from `AppLocalizations` in `package:dostr_flutter/l10n/app_localizations.dart`, and throw when its delegate is missing. Add `dostr_flutter.AppLocalizations.delegate` next to `GlobalMaterialLocalizations.delegates` from `material_ui`, which covers the Material, Cupertino and widgets texts. Don't use `AppLocalizations.localizationsDelegates`: gen-l10n fills it with the `flutter_localizations` delegates, which `material_ui` widgets don't read. See Flutter's [internationalization guide](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization).

It ships 13 locales: `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `pl`, `pt`, `pt_BR`, `ru`, `sk` and `zh`. `NLocaleSwitcher` (a button that opens a dialog) and `NLocaleSwitcherDropdown` let the user pick one of them and pass it to `onLocaleChanged`. Applying it to `MaterialApp.locale` is up to you.

## Widgets

Each widget takes the `DostrFlutter` as `dostrFlutter`.

- `NLogin`: the login form. A NIP-05 address or an npub logs in read-only, an nsec with the private key. It also offers the browser extension (on the web only), a `bunker://` url and the signer app (on Android only). Each method has an `enable...Login` flag, and `enablePubkeyLogin: false` hides both the NIP-05 and npub fields. Pass a `NostrConnect` from `dostrFlutter.bunkers.createNostrConnect(...)` as `nostrConnect` to also show a `nostrconnect://` QR code, and a `Nip46ClientMetadata` as `clientMetadata` to name your app to the bunker. `onLoggedIn` runs once an account is logged in.
- `NUserProfile`: the banner, picture, name and NIP-05 of a profile, with a logout button on the logged account.
- `NPicture`, `NName` and `NBanner`: the picture, name or banner alone. Without a picture, `NPicture` shows an initial on a color derived from the pubkey.
- `NSwitchAccount`: the accounts, with a tap to switch and a logout for the others. Give it `onAddAccount` to show an add account button.
- `NPendingRequests`: a floating panel of the requests waiting on the logged account's external signer, where the user can cancel them. It is a `Positioned`, so put it in a `Stack` over your content.

The profile widgets show the logged account unless given a `pubkey`. Pass a `metadata` (`Metadata.fromEvent(event)`) when you already have the profile, to skip the fetch.

## Saving accounts

`restoreAccountsState()` logs the saved accounts in again and switches to the one that was logged last. `saveAccountsState()` saves them. `NLogin`, `NSwitchAccount` and `NUserProfile` call it themselves, so call it only after changing `accounts` from your own code.

The accounts are written to [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage), private keys included, under `accountsKey` (`ndk_flutter_accounts`, or `dev_ndk_flutter_accounts` in debug builds). Pass a `FlutterSecureStorage` as `storage` to change its options. NIP-07, NIP-46 and NIP-55 accounts come back without asking the signer again. An account with any other external signer is not saved.

## Coming from `ndk_flutter`

`package:ndk_flutter/ndk_flutter.dart` is now `package:dostr_flutter/dostr_flutter.dart`. `NdkFlutter` is now `DostrFlutter`, and the widgets take it as `dostrFlutter` instead of `ndkFlutter`. `NdkEventSigner`, `NdkEventSignerFactory` and `NdkEventVerifier` are now `DostrEventSigner`, `DostrEventSignerFactory` and `DostrEventVerifier`. Saved accounts are still read from `ndk_flutter_accounts`, so users stay logged in.

## TODO

- [ ] NUserProfile optionnal show nsec and copy
- [ ] NUserProfile show the letter in the Picture and make it as big as possible

## Need more Widgets

Open an Issue
