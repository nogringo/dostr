import 'package:http/http.dart' as http;
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:test/test.dart';

import 'cashu_test_tools.dart';

void main() {
  setUp(() {});

  group('dev tests', () {
    test('fund', () async {
      final mintUrl = 'http://127.0.0.1:8085';

      final cashu = CashuTestTools.httpCashu();

      final fundResponse = await cashu.initiateFund(
        mintUrl: mintUrl,
        amount: 52,
        unit: 'sat',
        method: 'bolt11',
      );

      print(fundResponse);
    });

    test('parse mint info', () async {
      final mintUrl = 'http://127.0.0.1:8085';

      final NdkHttp httpRequestDS = NdkHttp(http.Client());

      final repo = CashuRepoImpl(client: httpRequestDS);

      final mintInfo = await repo.getMintInfo(mintUrl: mintUrl);

      print(mintInfo);
    });
  }, skip: true);
}
