import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_blossom/dostr_blossom.dart';
import 'package:dostr_signer/dostr_signer.dart';

Blossom blossomFor(Accounts accounts, {AuthHandler? authHandler}) => Blossom(
  accounts: accounts,
  signerFactory: const Bip340SignerFactory(),
  authHandler: authHandler,
  getUserServerList: (_) async => null,
);
