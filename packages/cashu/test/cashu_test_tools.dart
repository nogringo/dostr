import 'package:ndk_core/data_layer/data_sources/http_request.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

import 'mocks/cashu_http_client_mock.dart';

class CashuTestTools {
  static Cashu mockHttpCashu({
    MockCashuHttpClient? customMockClient,
    CashuStorage? customStorage,
    CashuUserSeedphrase? seedPhrase,
    CashuRepo? customRepo,
  }) {
    final MockCashuHttpClient mockClient =
        customMockClient ?? MockCashuHttpClient();
    final HttpRequestDS httpRequestDS = HttpRequestDS(mockClient);

    final CashuRepo cashuRepo =
        customRepo ?? CashuRepoImpl(client: httpRequestDS);

    final CashuStorage storage = customStorage ?? MemCashuStorage();

    final derivation = DartCashuKeyDerivation();

    final cashu = Cashu.withDependencies(
      cashuUserSeedphrase: seedPhrase,
      walletsRepo: MemWalletsRepo(),
      cashuRepo: cashuRepo,
      storage: storage,
      cashuKeyDerivation: derivation,
    );
    return cashu;
  }
}
