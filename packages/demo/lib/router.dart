import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:dostr_demo/l10n/app_localizations_context.dart';

import 'accounts_page.dart';
import 'blossom_page.dart';
import 'home_page.dart';
import 'main.dart';
import 'nip49_page.dart';
import 'nip77_page.dart';
import 'profile_page.dart';
import 'relays_page.dart';
import 'widgets_demo_page.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/', redirect: (_, __) => '/home'),
    GoRoute(path: '/home', builder: (context, state) => const HomePage()),
    GoRoute(
      path: '/accounts',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.tabAccounts)),
        body: const AccountsPage(),
      ),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.tabProfile)),
        body: ProfilePage(
          dostrFlutter: dostrFlutter,
          getLoggedPubkey: () => accounts.getPublicKey(),
          initialPubkey:
              state.extra as String? ?? state.uri.queryParameters['pubkey'],
        ),
      ),
    ),
    GoRoute(
      path: '/relays',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.tabRelays)),
        body: const RelaysPage(),
      ),
    ),
    GoRoute(
      path: '/blossom',
      builder: (context, state) => const BlossomMediaPage(),
    ),
    GoRoute(
      path: '/widgets',
      builder: (context, state) => const WidgetsDemoPage(),
    ),
    GoRoute(path: '/nip49', builder: (context, state) => const Nip49Page()),
    GoRoute(path: '/nip77', builder: (context, state) => const Nip77Page()),
  ],
);
