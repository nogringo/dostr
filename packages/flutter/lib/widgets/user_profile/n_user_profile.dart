import 'package:material_ui/material_ui.dart';
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_flutter/l10n/app_localizations.dart';
import 'package:dostr_flutter/dostr_flutter.dart';

class NUserProfile extends StatelessWidget {
  final DostrFlutter dostrFlutter;
  final String? pubkey;
  final Metadata? metadata;
  final bool showLogoutButton;
  final bool showName;
  final bool showNip05Indicator;
  final bool showNip05;
  final VoidCallback? onLogout;

  Accounts get _accounts => dostrFlutter.accounts;

  String? get profilePubkey =>
      metadata?.pubKey ?? pubkey ?? _accounts.getPublicKey();

  const NUserProfile({
    super.key,
    required this.dostrFlutter,
    this.pubkey,
    this.metadata,
    this.showLogoutButton = true,
    this.showName = true,
    this.showNip05Indicator = true,
    this.showNip05 = true,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    if (profilePubkey == null) return Container();

    // If metadata is provided, use it directly
    if (metadata != null) {
      return _buildProfile(context, metadata);
    }

    // Otherwise, load metadata
    return FutureBuilder(
      future: dostrFlutter.loadMetadata(profilePubkey!),
      builder: (context, snapshot) {
        return _buildProfile(context, snapshot.data);
      },
    );
  }

  Widget _buildProfile(BuildContext context, Metadata? metadata) {
    final name =
        metadata?.tryGetName() ?? dostrFlutter.formatNpub(profilePubkey!);
    final nip05 = metadata?.cleanNip05;

    // Check if this is the logged account
    final isLoggedAccount = profilePubkey == _accounts.getPublicKey();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 100,
                    width: double.maxFinite,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: NBanner(
                        dostrFlutter: dostrFlutter,
                        pubkey: profilePubkey,
                        metadata: metadata,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Visibility(
                  visible: showLogoutButton && isLoggedAccount,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          _accounts.logout();

                          if (_accounts.accounts.isNotEmpty) {
                            final pubkey =
                                _accounts.accounts.values.first.pubkey;
                            _accounts.switchAccount(pubkey: pubkey);
                          }

                          await dostrFlutter.saveAccountsState();

                          if (onLogout != null) onLogout!();
                        },
                        label: Text(AppLocalizations.of(context)!.logout),
                        icon: Icon(Icons.logout),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8),
              ],
            ),
            Positioned(
              bottom: 0,
              left: 32,
              child: ClipOval(
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: EdgeInsets.all(8),
                  child: NPicture(
                    dostrFlutter: dostrFlutter,
                    metadata: metadata,
                    pubkey: profilePubkey,
                    circleAvatarRadius: 40,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (showName || showNip05) SizedBox(height: 16),
        if (showName)
          Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.displaySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showNip05Indicator && nip05 != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.verified,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
        if (showNip05 && nip05 != null)
          Text(nip05, style: TextStyle(color: Theme.of(context).disabledColor)),
      ],
    );
  }
}
