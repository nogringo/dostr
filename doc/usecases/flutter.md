---
icon: device-mobile
label: Flutter
order: 70
---

# Flutter

[`dostr_flutter`](https://pub.dev/packages/dostr_flutter) gives a Flutter app ready-made Nostr widgets (login, profiles, account switcher, pending signer requests) and keeps its logged in accounts across restarts.

```yaml
dependencies:
  dostr_flutter: ^0.10.3-dev.2
  dostr_core: ^0.11.0-dev.2
  dostr_accounts: ^0.1.0
```

It re-exports [`dostr_nip07`](https://pub.dev/packages/dostr_nip07), [`dostr_nip55`](https://pub.dev/packages/dostr_nip55) and [`dostr_web_crypto`](https://pub.dev/packages/dostr_web_crypto).

## Example

```dart main.dart
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_flutter/l10n/app_localizations.dart' as dostr_flutter;
import 'package:flutter/material.dart';

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
      localizationsDelegates:
          dostr_flutter.AppLocalizations.localizationsDelegates,
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

`DostrFlutter` also holds `bunkers`, the `Bunkers` of [`dostr_nip46`](https://pub.dev/packages/dostr_nip46), and a `metadataFetcher`. The widgets read profiles through `dostrFlutter.loadMetadata`, which asks the write relays of each pubkey with a `MetadataFetcher` of [Fetchers](/usecases/fetchers.md). Pass your own `metadataFetcher` to share its cache with the rest of the app.

To answer NIP-42 authentication, give the same `Accounts` to the `RelayManager`, see [Relay authentication](/usecases/accounts.md#relay-authentication).

## Localization

The widgets read their texts from `AppLocalizations` in `package:dostr_flutter/l10n/app_localizations.dart`, and throw when its delegate is missing. `localizationsDelegates` holds it along with Flutter's Material, Cupertino and widgets delegates. If your app has its own localizations, add `dostr_flutter.AppLocalizations.delegate` to your list instead.

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
