import 'package:http/http.dart' as http;
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

import 'mocks/cashu_http_client_mock.dart';

class CashuTestTools {
  /// A wallet that talks to real mints, with an in-memory storage.
  static Cashu httpCashu({
    CashuUserSeedphrase? seedPhrase,
    WalletsRepo? walletsRepo,
  }) => Cashu(
    cashuUserSeedphrase: seedPhrase,
    walletsRepo: walletsRepo ?? StubWalletsRepo(),
    cashuRepo: CashuRepoImpl(client: NdkHttp(http.Client())),
    storage: MemCashuStorage(),
    cashuKeyDerivation: DartCashuKeyDerivation(),
  );

  static Cashu mockHttpCashu({
    MockCashuHttpClient? customMockClient,
    CashuStorage? customStorage,
    CashuUserSeedphrase? seedPhrase,
    CashuRepo? customRepo,
  }) {
    final MockCashuHttpClient mockClient =
        customMockClient ?? MockCashuHttpClient();
    final NdkHttp httpRequestDS = NdkHttp(mockClient);

    final CashuRepo cashuRepo =
        customRepo ?? CashuRepoImpl(client: httpRequestDS);

    final CashuStorage storage = customStorage ?? MemCashuStorage();

    final derivation = DartCashuKeyDerivation();

    final cashu = Cashu(
      cashuUserSeedphrase: seedPhrase,
      walletsRepo: MemWalletsRepo(),
      cashuRepo: cashuRepo,
      storage: storage,
      cashuKeyDerivation: derivation,
    );
    return cashu;
  }
}
