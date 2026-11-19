import 'dart:convert';

import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip07/dostr_nip07.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:dostr_nip55/dostr_nip55.dart';
import 'package:dostr_noble/dostr_noble.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

/// Writes the logged accounts of [accounts] to [storage] under [accountsKey],
/// and logs them in again. A restored NIP-46 signer reaches its bunker through
/// [relayReqs] and [relayPublishes], and passes its auth challenges to
/// [bunkerAuthCallback].
///
/// Each account is saved as `ndk_flutter` saved it, so that its users stay
/// logged in.
class AccountsStorage {
  final FlutterSecureStorage storage;
  final Accounts accounts;
  final RelayReqs relayReqs;
  final RelayPublishes relayPublishes;
  final void Function(String url) bunkerAuthCallback;

  AccountsStorage({
    required this.storage,
    required this.accounts,
    required this.relayReqs,
    required this.relayPublishes,
    required this.bunkerAuthCallback,
  });

  Future<void> save() => storage.write(
    key: accountsKey,
    value: jsonEncode({
      'loggedAccount': accounts.loggedPubkey,
      'accounts': [
        for (final signer in accounts.accounts.values) ?_saved(signer),
      ],
    }),
  );

  /// Skips an account it cannot read back, such as one of a kind it does not
  /// know or with an invalid key, and one that is already logged in.
  Future<void> restore() async {
    final saved = await storage.read(key: accountsKey);
    if (saved == null) return;
    final state = jsonDecode(saved);

    if (state case {'accounts': final List<Object?> savedAccounts}) {
      for (final account in savedAccounts) {
        final NostrSigner? signer;
        try {
          signer = _restored(account);
        } on FormatException {
          continue;
        }
        if (signer != null && !accounts.hasAccount(signer.publicKey)) {
          accounts.addAccount(signer: signer);
        }
      }
    }

    if (state case {
      'loggedAccount': final String pubkey,
    } when accounts.hasAccount(pubkey)) {
      accounts.switchAccount(pubkey: pubkey);
    }
  }

  static Map<String, String?>? _saved(NostrSigner signer) {
    Map<String, String?> saved(String kind, [String? signerSeed]) => {
      'kind': kind,
      'pubkey': signer.publicKey,
      'signerSeed': signerSeed,
    };

    return switch (signer) {
      Nip07Signer() => saved('nip07'),
      Nip55Signer(:final signerApp) => saved('nip55', signerApp.package),
      Nip46Signer(:final connection) => saved('bunker', jsonEncode(connection)),
      Bip340Signer(privateKey: final String privateKey) ||
      WebSigner(
        privateKey: final String privateKey,
      ) => saved('privkey', privateKey),
      Bip340Signer() || WebSigner() => saved('pubkey'),
      _ => null,
    };
  }

  NostrSigner? _restored(Object? account) => switch (account) {
    // checked first, since a NIP-46 signer listens to its relays once built
    {'pubkey': final String pubkey} when accounts.hasAccount(pubkey) => null,
    {'kind': 'nip07', 'pubkey': final String pubkey} => Nip07Signer(
      publicKey: pubkey,
    ),
    // `amber` is what NIP-55 accounts were saved as before
    {
      'kind': 'nip55' || 'amber',
      'pubkey': final String pubkey,
      'signerSeed': final String package,
    } =>
      Nip55Signer(
        publicKey: pubkey,
        signerApp: Nip55SignerApp(package: package),
      ),
    {'kind': 'nip55' || 'amber', 'pubkey': final String pubkey} => Nip55Signer(
      publicKey: pubkey,
      signerApp: const Nip55SignerApp(),
    ),
    {
      'kind': 'bunker',
      'pubkey': final String pubkey,
      'signerSeed': final String connection,
    } =>
      Nip46Signer(
        connection: BunkerConnection.fromJson(jsonDecode(connection)),
        publicKey: pubkey,
        relayReqs: relayReqs,
        relayPublishes: relayPublishes,
        authCallback: bunkerAuthCallback,
        signerFactory: accounts.signerFactory,
      ),
    {'kind': 'pubkey', 'pubkey': final String pubkey} =>
      accounts.signerFactory.readOnly(pubkey),
    {'kind': 'privkey', 'signerSeed': final String privateKey} =>
      accounts.signerFactory.create(privateKey),
    _ => null,
  };
}
