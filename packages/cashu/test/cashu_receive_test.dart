import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_wallets/ndk_wallets.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import 'cashu_test_tools.dart';
import 'mocks/cashu_http_client_mock.dart';

const devMintUrl = 'https://dev.mint.camelus.app';
const failingMintUrl = 'https://mint.example.com';
const mockMintUrl = "https://mock.mint";

void main() {
  setUp(() {});

  group('receive tests - exceptions ', () {
    test("invalid token", () {
      final ndk = Ndk.emptyBootstrapRelaysConfig();
      final cashu = Cashu(ndk);

      final rcvStream = cashu.receive("cashuBinvalidtoken");
      expect(() async => await rcvStream.last, throwsA(isA<Exception>()));
    });

    test("empty token", () async {
      final ndk = Ndk.emptyBootstrapRelaysConfig();
      final cashu = Cashu(ndk);

      final rcvStream = cashu.receive(
        "cashuBo2FteBxodHRwczovL2Rldi5taW50LmNhbWVsdXMuYXBwYXVjc2F0YXSBomFpQGFwgaRhYQBhc2BhY0BhZKNhZUBhc0BhckA",
      );

      expect(() async => await rcvStream.last, throwsA(isA<Exception>()));
    });

    test("invalid mint", skip: true, () async {
      final ndk = Ndk.emptyBootstrapRelaysConfig();
      final cashu = Cashu(ndk);

      final rcvStream = cashu.receive(
        "cashuBo2FtdGh0dHBzOi8vbWludC5pbnZhbGlkYXVjc2F0YXSBomFpSABV3vjPJfyNYXCBpGFhAWFzeEBmYmMxYWY4ZTk1YWQyZTVjMGQzY2U3MTMxNjI3MDBkOGNmN2NhNDQ2Njc1ZTE5NTc0NWE5ZWYzMDI1Zjc0NjdhYWNYIQJYTRSL3snLOVtf2OECtcqM_y7kG1VCQnVeWc9BPzP4zGFko2FlWCAlHMDORr2HAR0NNMsV4tB3s09bCB_s35QvHIEVkqed3mFzWCBLAh8gJ0J0uv7WzGkFC9gn4jZc7sFTpZvEgnitZ6ijrGFyWCC9QCslHjMWBU_2TWwnUNXj-rM7-iP6_8RqxiJMsa1Dcg",
      );

      expect(() async => await rcvStream.last, throwsA(isA<Exception>()));
    });
  });

  group('receive', () {
    test("receive integration, double spend", skip: true, () async {
      final cache = MemCashuStorage();
      final cache2 = MemCashuStorage();

      final client = NdkHttp(http.Client());
      final cashuRepo = CashuRepoImpl(client: client);
      final cashuRepo2 = CashuRepoImpl(client: client);
      final derivation = DartCashuKeyDerivation();
      final walletsRepo = MemWalletsRepo();

      final cashu = Cashu.withDependencies(
        cashuRepo: cashuRepo,
        walletsRepo: walletsRepo,
        storage: cache,
        cashuKeyDerivation: derivation,
        cashuUserSeedphrase: CashuUserSeedphrase(
          seedPhrase: CashuSeed.generateSeedPhrase(),
        ),
      );
      final walletsRepo2 = MemWalletsRepo();

      final cashu2 = Cashu.withDependencies(
        cashuRepo: cashuRepo2,
        walletsRepo: walletsRepo2,
        storage: cache2,
        cashuKeyDerivation: derivation,
        cashuUserSeedphrase: CashuUserSeedphrase(
          seedPhrase: CashuSeed.generateSeedPhrase(),
        ),
      );

      const fundAmount = 32;
      const fundUnit = "sat";

      final draftTransaction = await cashu.initiateFund(
        mintUrl: devMintUrl,
        amount: fundAmount,
        unit: fundUnit,
        method: "bolt11",
      );
      final transactionStream = cashu.retrieveFunds(
        draftTransaction: draftTransaction,
      );

      final transaction = await transactionStream.last;
      expect(transaction.state, WalletTransactionState.completed);

      final spending = await cashu.initiateSpend(
        mintUrl: devMintUrl,
        amount: 16,
        unit: fundUnit,
      );
      final token = spending.token.toV4TokenString();

      final rcvStream = cashu2.receive(token);

      await expectLater(
        rcvStream,
        emitsInOrder([
          isA<CashuWalletTransaction>().having(
            (t) => t.state,
            'state',
            WalletTransactionState.pending,
          ),
          isA<CashuWalletTransaction>()
              .having((t) => t.state, 'state', WalletTransactionState.completed)
              .having((t) => t.transactionDate!, 'transactionDate', isA<int>()),
        ]),
      );

      final balance = await cashu2.getBalanceMintUnit(
        unit: fundUnit,
        mintUrl: devMintUrl,
      );

      expect(balance, equals(16));

      // try to double spend the same token
      final rcvStream2 = cashu2.receive(token);

      expect(() async => await rcvStream2.last, throwsA(isA<Exception>()));
    });
  });

  group('receive fees', () {
    // 1 sat per input
    MockCashuHttpClient feeMint() => MockCashuHttpClient()
      ..setCustomResponse(
        'GET',
        '/v1/keysets',
        http.Response(
          jsonEncode({
            'keysets': [
              {
                'id': '00c726786980c4d9',
                'unit': 'sat',
                'active': true,
                'input_fee_ppk': 1000,
              },
            ],
          }),
          200,
        ),
      );

    String tokenOf(List<int> amounts) => CashuToken(
      proofs: [
        for (final (i, amount) in amounts.indexed)
          CashuProof(
            keysetId: '00c726786980c4d9',
            amount: amount,
            secret: 'secret $i',
            unblindedSig: '02${'ab' * 32}',
          ),
      ],
      memo: '',
      unit: 'sat',
      mintUrl: 'http://mock.mint',
    ).toV4TokenString();

    Cashu cashuFor(MockCashuHttpClient client) => CashuTestTools.mockHttpCashu(
      customMockClient: client,
      seedPhrase: CashuUserSeedphrase(
        seedPhrase: CashuSeed.generateSeedPhrase(),
      ),
    );

    test('asks for outputs worth the token minus the input fees', () async {
      final client = feeMint();
      final events = <CashuWalletTransaction>[];

      // the mock has no swap endpoint, so the receive fails after the request
      await expectLater(
        cashuFor(client).receive(tokenOf([4, 2])).forEach(events.add),
        throwsException,
      );

      final swap = client.getRequestsForPath('/v1/swap').single;
      final outputs = jsonDecode(swap.body)['outputs'] as List<dynamic>;
      expect(outputs.map((output) => output['amount']), [4]);
      expect(events.first.changeAmount, 4);
    });

    test('refuses a token that does not cover the fees', () async {
      final client = feeMint();

      await expectLater(
        cashuFor(client).receive(tokenOf([1, 1])).last,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('does not cover the 2 sat of mint fees'),
          ),
        ),
      );
      expect(client.getRequestsForPath('/v1/swap'), isEmpty);
    });
  });
}
