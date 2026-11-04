import 'providers/bolt12/bolt12_wallet.dart';
import 'providers/lnbits/lnbits_wallet.dart';
import 'providers/lnurl/lnurl_wallet.dart';
import 'wallet.dart';
import 'wallet_type.dart';

/// Rebuilds a stored wallet of one [WalletType], see
/// [WalletFactory.registerType].
typedef WalletFromStorage =
    Wallet Function({
      required String id,
      required String name,
      required Set<String> supportedUnits,
      required Map<String, dynamic> metadata,
    });

/// Factory for deserializing wallets from storage
/// Storage packages use this to convert stored data back to Wallet objects
/// Each wallet type implements a static fromStorage method that handles its specific deserialization
class WalletFactory {
  static final Map<WalletType, WalletFromStorage> _fromStorage = {
    WalletType.LNURL: LnurlWallet.fromStorage,
    WalletType.BOLT12: Bolt12Wallet.fromStorage,
    WalletType.LNBITS: LnBitsWallet.fromStorage,
  };

  /// Registers how [fromStorage] rebuilds wallets of [type]. ndk_cashu and
  /// ndk_nwc register theirs when their usecase or wallet provider is created.
  static void registerType(WalletType type, WalletFromStorage fromStorage) {
    _fromStorage[type] = fromStorage;
  }

  /// Creates a wallet instance from storage data
  /// Delegates to the fromStorage method registered for the wallet type
  static Wallet fromStorage({
    required String id,
    required String name,
    required WalletType type,
    required Set<String> supportedUnits,
    required Map<String, dynamic> metadata,
  }) {
    final fromStorage = _fromStorage[type];
    if (fromStorage == null) {
      throw StateError(
        'No wallet type registered for $type, '
        'create its usecase or wallet provider first',
      );
    }
    return fromStorage(
      id: id,
      name: name,
      supportedUnits: supportedUnits,
      metadata: metadata,
    );
  }
}
