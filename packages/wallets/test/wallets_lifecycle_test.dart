import 'package:ndk/ndk.dart';
import 'package:ndk_wallets/ndk_wallets.dart';
import 'package:test/test.dart';

void main() {
  test('Ndk lifecycle hooks drive Wallets', () async {
    final ndk = Ndk.emptyBootstrapRelaysConfig();
    final wallets = Wallets(ndk, providers: const []);

    await ndk.setBackgrounded(true);
    expect(wallets.isBackgrounded, isTrue);
    await ndk.setBackgrounded(false);
    expect(wallets.isBackgrounded, isFalse);
    await ndk.destroy();
  });
}
