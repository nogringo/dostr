import 'package:ndk/ndk.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_nwc/ndk_nwc.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

/// Wallet usecases, created on first use so that commands without wallets
/// open no wallet connection and resume no Cashu quote.
class CliWallets {
  CliWallets(this._ndk, this._repository);

  final Ndk _ndk;
  final WalletsRepo _repository;

  late final Nwc nwc = Nwc(_ndk);

  late final Cashu cashu = Cashu(_ndk, walletsRepo: _repository);

  late final Wallets wallets = Wallets(
    _ndk,
    repository: _repository,
    providers: [
      CashuWalletProvider(cashu),
      NwcWalletProvider(nwc),
      LnurlWalletProvider(_ndk.lnurl),
      const Bolt12WalletProvider(),
      LnBitsWalletProvider(),
    ],
  );
}
