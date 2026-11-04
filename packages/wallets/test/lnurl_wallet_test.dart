import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk/data_layer/data_sources/http_request.dart';
import 'package:ndk/data_layer/repositories/lnurl_http_impl.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk_wallets/ndk_wallets.dart';
import 'package:test/test.dart';

void main() {
  group('LNURL wallet', () {
    test('failed metadata fetch does not add an LNURL wallet', () async {
      const identifier = 'name@domain.com';
      final link = Lnurl.getLud16LinkFromLud16(identifier)!;
      final endpoint = _LnurlEndpoint(link, http.Response('not found', 404));
      final lnurl = Lnurl(
        transport: LnurlTransportHttpImpl(HttpRequestDS(endpoint.client)),
      );
      final repository = MemWalletsRepo();
      final wallets = Wallets.withDependencies(
        providers: [LnurlWalletProvider(lnurl)],
        repository: repository,
      );
      addTearDown(wallets.dispose);
      await wallets.getWallets();

      final wallet = wallets.createWallet(
        id: 'lnurl-wallet',
        name: identifier,
        type: WalletType.LNURL,
        supportedUnits: {'sat'},
        metadata: {'identifier': identifier},
      );

      await expectLater(wallets.addWallet(wallet), throwsException);
      expect(await repository.getWallets(), isEmpty);
      expect(await wallets.getWallets(), isEmpty);
    });

    test('reconnect checks HTTP endpoint even with cached metadata', () async {
      const identifier = 'name@domain.com';
      final link = Lnurl.getLud16LinkFromLud16(identifier)!;
      final endpoint = _LnurlEndpoint(link, http.Response('unavailable', 503));
      final lnurl = Lnurl(
        transport: LnurlTransportHttpImpl(HttpRequestDS(endpoint.client)),
      );
      final repository = MemWalletsRepo();
      final wallet = LnurlWallet(
        id: 'lnurl-wallet',
        name: identifier,
        supportedUnits: const {'sat'},
        identifier: identifier,
        lnurlPayUrl: link,
        minSendable: 1000,
        maxSendable: 100000,
        metadataFetchedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await repository.storeWallet(wallet);
      final wallets = Wallets.withDependencies(
        providers: [LnurlWalletProvider(lnurl)],
        repository: repository,
      );
      addTearDown(wallets.dispose);
      await wallets.getWallets();

      await expectLater(wallets.reconnectWallet(wallet.id), throwsException);
      expect(endpoint.calls, 1);
    });
  });
}

class _LnurlEndpoint {
  final String link;
  final http.Response response;
  int calls = 0;
  late final MockClient client = MockClient((request) async {
    if (request.method == 'GET' &&
        request.url == Uri.parse(link) &&
        request.headers['Accept'] == 'application/json') {
      calls++;
      return response;
    }
    return http.Response('unexpected request', 500);
  });

  _LnurlEndpoint(this.link, this.response);
}
