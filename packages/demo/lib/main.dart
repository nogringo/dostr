import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_demo/l10n/app_localizations_context.dart';
import 'package:dostr_demo/router.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';
import 'package:dostr_flutter/l10n/app_localizations.dart' as dostr_flutter;
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_nip77/dostr_nip77.dart';
import 'package:dostr_rust_verifier/dostr_rust_verifier.dart';

import 'l10n/generated/demo_localizations.dart';
import 'local_events.dart';

late RelayManager relayManager;
late RelayReqs relayReqs;
late RelayPublishes relayPublishes;
late Accounts accounts;
late Nip65Fetcher nip65Fetcher;
late DostrFlutter dostrFlutter;
late Nip77 nip77;

/// the events this session fetched, which NIP-77 compares with a relay's
final localEvents = LocalEvents();

final localeNotifier = ValueNotifier<Locale>(const Locale('en'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  Logger.setLogLevel(LogLevel.info);

  accounts = Accounts(const DostrEventSignerFactory());
  relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
    accounts: accounts,
  );
  relayReqs = RelayReqs(
    relayManager: relayManager,
    eventVerifier: kIsWeb ? WebEventVerifier() : RustEventVerifier(),
  );
  relayPublishes = RelayPublishes(relayManager: relayManager);
  nip65Fetcher = Nip65Fetcher(reqs: relayReqs);
  nip77 = Nip77(
    relayManager: relayManager,
    loadEventIds: localEvents.loadEventIds,
    loadEvent: localEvents.loadEvent,
  );

  // The default data protection keychain needs an entitlement ad-hoc signing can't grant.
  const secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  dostrFlutter = DostrFlutter(
    accounts: accounts,
    relayReqs: relayReqs,
    relayPublishes: relayPublishes,
    metadataFetcher: MetadataFetcher(
      reqs: relayReqs,
      nip65Fetcher: nip65Fetcher,
    ),
    storage: secureStorage,
  );
  await dostrFlutter.restoreAccountsState();

  GoRouter.optionURLReflectsImperativeAPIs = true;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) => MaterialApp.router(
        onGenerateTitle: (context) => context.l10n.appName,
        locale: locale,
        localizationsDelegates: const [
          DemoLocalizations.delegate,
          dostr_flutter.AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        // Use dostr_flutter's locale list: it's the superset that includes the
        // extra locales (fi, pt, pt_BR) translated in that package. The demo
        // shell falls back to English for those via the delegate above.
        supportedLocales: dostr_flutter.AppLocalizations.supportedLocales,
        routerConfig: appRouter,
        // media_kit_video's controls still use package:flutter/material.dart.
        // ignore: deprecated_member_use
        builder: (context, child) => MaterialUiCompatibilityBridge(
          child: Stack(
            children: [
              SafeArea(top: false, child: child ?? const SizedBox.shrink()),
              NPendingRequests(dostrFlutter: dostrFlutter),
            ],
          ),
        ),
      ),
    );
  }
}
