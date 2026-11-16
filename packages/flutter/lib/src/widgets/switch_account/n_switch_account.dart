import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:material_ui/material_ui.dart';

import '../../../dostr_flutter.dart';
import '../../../l10n/app_localizations.dart';

class NSwitchAccount extends StatefulWidget {
  final DostrFlutter dostrFlutter;
  final void Function(String pubkey)? onAccountSwitch;
  final void Function(String pubkey)? onAccountRemove;
  final void Function()? onAddAccount;
  final void Function(String pubkey)? beforeAccountSwitch;
  final void Function(String pubkey)? beforeAccountRemove;

  const NSwitchAccount({
    super.key,
    required this.dostrFlutter,
    this.onAccountSwitch,
    this.onAccountRemove,
    this.onAddAccount,
    this.beforeAccountSwitch,
    this.beforeAccountRemove,
  });

  @override
  State<NSwitchAccount> createState() => _NSwitchAccountState();
}

class _NSwitchAccountState extends State<NSwitchAccount> {
  Accounts get _accounts => widget.dostrFlutter.accounts;

  Widget _signerChip(BuildContext context, NostrSigner account) {
    final l10n = AppLocalizations.of(context)!;

    final (label, backgroundColor) = switch (account) {
      Nip07Signer() => (l10n.extension, Colors.orange),
      Nip55Signer() => (l10n.signerApp, Colors.purple),
      Nip46Signer() => (l10n.bunker, Colors.green),
      NostrSigner(canSign: false) => (l10n.readOnly, Colors.blue),
      Bip340Signer() || WebSigner() => (l10n.nsec, Colors.red),
      _ => (l10n.signer, Colors.grey),
    };

    return Chip(
      label: Text(label),
      backgroundColor: backgroundColor.withValues(alpha: 0.2),
      side: BorderSide(color: backgroundColor),
      shape: StadiumBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts.accounts.values.toList();
    final loggedPubkey = _accounts.loggedPubkey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...accounts.map((account) {
          final pubkey = account.publicKey;
          final isLoggedAccount = loggedPubkey == pubkey;

          Widget? subtitle;
          void Function()? onTap;
          if (!isLoggedAccount) {
            subtitle = Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  widget.beforeAccountRemove?.call(pubkey);
                  _accounts.removeAccount(pubkey: pubkey);
                  widget.dostrFlutter.saveAccountsState();
                  setState(() {});
                  widget.onAccountRemove?.call(pubkey);
                },
                child: Text(AppLocalizations.of(context)!.logout),
              ),
            );

            onTap = () {
              widget.beforeAccountSwitch?.call(pubkey);
              _accounts.switchAccount(pubkey: pubkey);
              widget.dostrFlutter.saveAccountsState();
              setState(() {});
              widget.onAccountSwitch?.call(pubkey);
            };
          }

          return ListTile(
            leading: NPicture(
              dostrFlutter: widget.dostrFlutter,
              pubkey: pubkey,
            ),
            title: NName(dostrFlutter: widget.dostrFlutter, pubkey: pubkey),
            subtitle: subtitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _signerChip(context, account),
                SizedBox(width: 8),
                Opacity(
                  opacity: isLoggedAccount ? 1 : 0,
                  child: Icon(
                    Icons.radio_button_checked,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            onTap: onTap,
          );
        }),
        if (widget.onAddAccount != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TextButton.icon(
              onPressed: widget.onAddAccount,
              label: Text(AppLocalizations.of(context)!.addAccount),
              icon: Icon(Icons.add_circle_outline),
            ),
          ),
      ],
    );
  }
}
