import 'package:flutter/material.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:dostr_demo/l10n/app_localizations_context.dart';
import 'package:dostr_flutter/dostr_flutter.dart';

const _clientMetadata = Nip46ClientMetadata(name: 'Dostr demo');

Future<void> showNLoginPopup({
  required BuildContext context,
  required DostrFlutter dostrFlutter,
  required VoidCallback onLoggedIn,
  String title = 'Log in',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
        title: Row(
          children: [
            Expanded(child: Text(title)),
            IconButton(
              tooltip: l10n.closeTooltip,
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: NLogin(
              dostrFlutter: dostrFlutter,
              clientMetadata: _clientMetadata,
              nostrConnect: dostrFlutter.bunkers.createNostrConnect(
                clientMetadata: _clientMetadata,
                relays: [
                  "wss://promenade.fiatjaf.com",
                  "wss://relay.ditto.pub",
                  "wss://relay.primal.net",
                  "wss://relay.nmail.li",
                ],
              ),
              onLoggedIn: () {
                Navigator.of(dialogContext).pop();
                onLoggedIn();
              },
            ),
          ),
        ),
      );
    },
  );
}
