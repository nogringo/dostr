import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_demo/l10n/app_localizations_context.dart';
import 'package:ndk_demo/router.dart';
import 'package:ndk_fetchers/ndk_fetchers.dart';
import 'package:ndk_flutter/l10n/app_localizations.dart' as ndk_flutter;
import 'package:ndk_flutter/ndk_flutter.dart';
import 'package:ndk_nip77/ndk_nip77.dart';
import 'package:ndk_rust_verifier/ndk_rust_verifier.dart';

import 'l10n/generated/sample_app_localizations.dart';
import 'local_events.dart';

late RelayManager relayManager;
late RelayReqs relayReqs;
late RelayPublishes relayPublishes;
late Accounts accounts;
late Nip65Fetcher nip65Fetcher;
late NdkFlutter ndkFlutter;
late Nip77 nip77;

/// the events this session fetched, which NIP-77 compares with a relay's
final localEvents = LocalEvents();

final localeNotifier = ValueNotifier<Locale>(const Locale('en'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  Logger.setLogLevel(LogLevel.info);

  accounts = Accounts(const NdkEventSignerFactory());
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
  ndkFlutter = NdkFlutter(
    accounts: accounts,
    relayReqs: relayReqs,
    relayPublishes: relayPublishes,
    metadataFetcher: MetadataFetcher(
      reqs: relayReqs,
      nip65Fetcher: nip65Fetcher,
    ),
    storage: secureStorage,
  );
  await ndkFlutter.restoreAccountsState();

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
          SampleAppLocalizations.delegate,
          ndk_flutter.AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Use ndk_flutter's locale list: it's the superset that includes the
        // extra locales (fi, pt, pt_BR) translated in that package. The sample
        // app shell falls back to English for those via the delegate above.
        supportedLocales: ndk_flutter.AppLocalizations.supportedLocales,
        routerConfig: appRouter,
        builder: (context, child) => Stack(
          children: [
            SafeArea(top: false, child: child ?? const SizedBox.shrink()),
            NPendingRequests(ndkFlutter: ndkFlutter),
          ],
        ),
      ),
    );
  }
}
