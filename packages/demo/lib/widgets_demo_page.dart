import 'package:dostr_core/dostr_core.dart' show cleanRelayUrls;
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n/app_localizations_context.dart';
import 'main.dart';

const _clientMetadata = Nip46ClientMetadata(name: 'Dostr demo');

const _colorDemoPubkeys = [
  '8f43b51ff660faf4039e9c9187394a06b62b719e609f02719c16668b56d7ca99',
  'e8c5dccad6e6898c02dff327737bdf40e9a808567d07d5d472c24ab1fab28f0b',
  '3b30053888927b763c02bf42b15db2731ec5bf4d63a55bdba68b30e0cae9b4c7',
  '6da556857c1d40eb6d548715371c7713642e37c92cd99da2b463e3d2b9c76466',
  '0b1aa16f9792a4c5f689e6d9df853c80d324aef4dcdbb18c39e8052da0425f65',
  'd4d5622db202a3b62c31ac6bad729282232e833839920bbbfdcc15f7b4d57e07',
];

class WidgetsDemoPage extends StatefulWidget {
  const WidgetsDemoPage({super.key});

  @override
  State<WidgetsDemoPage> createState() => _WidgetsDemoPageState();
}

class _WidgetsDemoPageState extends State<WidgetsDemoPage> {
  bool _showLogin = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loggedPubkey = accounts.loggedPubkey;
    final isLoggedIn = loggedPubkey != null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.widgetsPageTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info message
            if (!isLoggedIn)
              Card(
                color: Colors.amber.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.widgetsLoginHint,
                          style: TextStyle(color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!isLoggedIn) const SizedBox(height: 24),

            // NName Widget Section
            _buildSection(
              title: 'NName',
              description: l10n.widgetsSectionNNameDescription,
              child: isLoggedIn
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Text(l10n.widgetsCurrentUser),
                            NName(dostrFlutter: dostrFlutter),
                          ],
                        ),
                      ),
                    )
                  : _buildPlaceholder('NName widget'),
            ),

            // NPicture Widget Section
            _buildSection(
              title: 'NPicture',
              description: l10n.widgetsSectionNPictureDescription,
              child: isLoggedIn
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Column(
                              children: [
                                NPicture(
                                  dostrFlutter: dostrFlutter,
                                  circleAvatarRadius: 30,
                                ),
                                const SizedBox(height: 8),
                                Text(l10n.widgetsSizeDefault),
                              ],
                            ),
                            Column(
                              children: [
                                NPicture(
                                  dostrFlutter: dostrFlutter,
                                  circleAvatarRadius: 40,
                                ),
                                const SizedBox(height: 8),
                                Text(l10n.widgetsSizeLarger),
                              ],
                            ),
                            Column(
                              children: [
                                NPicture(
                                  dostrFlutter: dostrFlutter,
                                  circleAvatarRadius: 50,
                                ),
                                const SizedBox(height: 8),
                                Text(l10n.widgetsSizeLarge),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildPlaceholder('NPicture widget'),
            ),

            // NBanner Widget Section
            _buildSection(
              title: 'NBanner',
              description: l10n.widgetsSectionNBannerDescription,
              child: isLoggedIn
                  ? Card(
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        height: 120,
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: NBanner(dostrFlutter: dostrFlutter),
                        ),
                      ),
                    )
                  : _buildPlaceholder('NBanner widget'),
            ),

            // NUserProfile Widget Section
            _buildSection(
              title: 'NUserProfile',
              description: l10n.widgetsSectionNUserProfileDescription,
              child: isLoggedIn
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: NUserProfile(
                          dostrFlutter: dostrFlutter,
                          showLogoutButton: false,
                        ),
                      ),
                    )
                  : _buildPlaceholder('NUserProfile widget'),
            ),

            // NSwitchAccount Widget Section
            _buildSection(
              title: 'NSwitchAccount',
              description: l10n.widgetsSectionNSwitchAccountDescription,
              child: isLoggedIn
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: NSwitchAccount(
                          dostrFlutter: dostrFlutter,
                          onAccountSwitch: (pubkey) {
                            setState(() {});
                          },
                          onAccountRemove: (pubkey) {
                            setState(() {});
                          },
                        ),
                      ),
                    )
                  : _buildPlaceholder('NSwitchAccount widget'),
            ),

            // NLogin Widget Section
            _buildSection(
              title: 'NLogin',
              description: l10n.widgetsSectionNLoginDescription,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_showLogin)
                        FilledButton.icon(
                          onPressed: () => setState(() => _showLogin = true),
                          icon: const Icon(Icons.login),
                          label: Text(l10n.widgetsShowLoginWidget),
                        ),
                      if (_showLogin) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.widgetsLoginWidgetTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _showLogin = false),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const Divider(),
                        NLogin(
                          dostrFlutter: dostrFlutter,
                          onLoggedIn: () {
                            setState(() => _showLogin = false);
                          },
                          enableNip07Login: false,
                          enableSignerAppLogin: false,
                          clientMetadata: _clientMetadata,
                          nostrConnect: dostrFlutter.bunkers.createNostrConnect(
                            clientMetadata: _clientMetadata,
                            relays: cleanRelayUrls([
                              "wss://promenade.fiatjaf.com",
                              "wss://relay.ditto.pub",
                              "wss://relay.primal.net",
                              "wss://relay.nmail.li",
                            ]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Color from pubkey demo
            _buildSection(
              title: 'StringColor',
              description: l10n.widgetsSectionGetColorDescription,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final pubkey in _colorDemoPubkeys)
                        _buildColorDemo(pubkey),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String description,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        child,
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPlaceholder(String widgetName) {
    final l10n = context.l10n;
    return Card(
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Text(
            l10n.widgetsRequiresLogin(widgetName),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      ),
    );
  }

  Widget _buildColorDemo(String pubkey) {
    final color = StringColor.fromHex(pubkey).toColor();
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 4),
        Text(pubkey.substring(0, 10), style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}
