import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_blossom/ndk_blossom.dart';
import 'package:ndk_signer/ndk_signer.dart';

Blossom blossomFor(Accounts accounts, {AuthHandler? authHandler}) => Blossom(
  accounts: accounts,
  eventSignerFactory: const Bip340EventSignerFactory(),
  authHandler: authHandler,
  getUserServerList: (_) async => null,
);
