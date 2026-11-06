import 'package:ndk/ndk.dart';
import 'package:ndk_blossom/ndk_blossom.dart';

Blossom blossomFor(Ndk ndk) => Blossom(
  accounts: ndk.accounts,
  eventSignerFactory: ndk.config.eventSignerFactory,
  authHandler: ndk.config.authHandler,
  getUserServerList: (pubkey) =>
      ndk.blossomUserServerList.getUserServerList(pubkeys: [pubkey]),
);
