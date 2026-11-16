import 'dart:convert';

import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip07/dostr_nip07.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:dostr_nip55/dostr_nip55.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'models/accounts.dart';

/// Writes the logged accounts of [accounts] to [storage] under [accountsKey],
/// and logs them in again. A restored NIP-46 signer reaches its bunker through
/// [relayReqs] and [relayPublishes].
class AccountsStorage {
  final FlutterSecureStorage storage;
  final Accounts accounts;
  final RelayReqs relayReqs;
  final RelayPublishes relayPublishes;

  AccountsStorage({
    required this.storage,
    required this.accounts,
    required this.relayReqs,
    required this.relayPublishes,
  });

  Future<void> save() async {
    final stored = NostrWidgetsAccounts(accounts: []);

    for (var account in accounts.accounts.values) {
      if (account.signer is Nip07Signer) {
        stored.accounts.add(
          NostrAccount(kind: AccountKinds.nip07, pubkey: account.pubkey),
        );
        continue;
      }

      if (account.signer is Nip55Signer) {
        // `signerSeed` holds the signer app package so
        // silent signing keeps working after restart.
        final signer = account.signer as Nip55Signer;
        stored.accounts.add(
          NostrAccount(
            kind: AccountKinds.nip55,
            pubkey: account.pubkey,
            signerSeed: signer.signerApp.package,
          ),
        );
        continue;
      }

      if (account.signer is Nip46Signer) {
        final signer = account.signer as Nip46Signer;
        stored.accounts.add(
          NostrAccount(
            kind: AccountKinds.bunker,
            pubkey: account.pubkey,
            signerSeed: jsonEncode(signer.connection),
          ),
        );
        continue;
      }

      if (account.signer
          case Bip340Signer(:final privateKey) ||
              WebSigner(:final privateKey)) {
        stored.accounts.add(
          privateKey == null
              ? NostrAccount(kind: AccountKinds.pubkey, pubkey: account.pubkey)
              : NostrAccount(
                  kind: AccountKinds.privkey,
                  pubkey: account.pubkey,
                  signerSeed: privateKey,
                ),
        );
      }
    }

    stored.loggedAccount = accounts.loggedPubkey;

    await storage.write(key: accountsKey, value: jsonEncode(stored));
  }

  Future<void> restore() async {
    final storedAccounts = await storage.read(key: accountsKey);

    if (storedAccounts == null) return;

    final stored = NostrWidgetsAccounts.fromJson(jsonDecode(storedAccounts));

    for (var account in stored.accounts) {
      if (accounts.hasAccount(account.pubkey)) continue;

      if (account.kind == AccountKinds.nip07) {
        final signer = Nip07Signer(publicKey: account.pubkey);
        accounts.addAccount(signer: signer);
        continue;
      }

      if (account.kind == AccountKinds.nip55) {
        accounts.addAccount(
          signer: Nip55Signer(
            publicKey: account.pubkey,
            // restore the signer app package captured at login (null for
            // legacy accounts -> Android routes through a compatible signer).
            signerApp: Nip55SignerApp(package: account.signerSeed),
          ),
        );
        continue;
      }

      if (account.kind == AccountKinds.bunker) {
        final signer = Nip46Signer(
          connection: BunkerConnection.fromJson(
            jsonDecode(account.signerSeed!),
          ),
          publicKey: account.pubkey,
          relayReqs: relayReqs,
          relayPublishes: relayPublishes,
          signerFactory: accounts.signerFactory,
        );
        accounts.addAccount(signer: signer);
        continue;
      }

      if (account.kind == AccountKinds.pubkey) {
        accounts.addAccount(
          signer: accounts.signerFactory.readOnly(account.pubkey),
        );
        continue;
      }

      if (account.kind == AccountKinds.privkey) {
        accounts.addAccount(
          signer: accounts.signerFactory.create(account.signerSeed!),
        );
        continue;
      }
    }

    if (stored.loggedAccount == null) return;
    if (!accounts.hasAccount(stored.loggedAccount!)) return;
    try {
      accounts.switchAccount(pubkey: stored.loggedAccount!);
    } catch (_) {
      // stored logged account could not be restored (e.g. stale/corrupted
      // state); ignore rather than crash app startup.
    }
  }
}
