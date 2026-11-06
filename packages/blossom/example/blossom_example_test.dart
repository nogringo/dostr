// ignore_for_file: avoid_print

import 'package:ndk/ndk.dart';
import 'package:ndk_blossom/ndk_blossom.dart';
import 'package:test/test.dart';

void main() async {
  test('download test', () async {
    final ndk = Ndk.defaultConfig();
    final blossom = Blossom(
      accounts: ndk.accounts,
      eventSignerFactory: ndk.config.eventSignerFactory,
      authHandler: ndk.config.authHandler,
      getUserServerList: (pubkey) =>
          ndk.blossomUserServerList.getUserServerList(pubkeys: [pubkey]),
    );

    final downloadResult = await blossom.getBlob(
      sha256:
          "b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553",
      serverUrls: ["https://cdn.hzrd149.com", "https://nostr.download"],
    );

    print(
      "file of type: ${downloadResult.mimeType}, size: ${downloadResult.data.length}",
    );

    expect(downloadResult.data.length, greaterThan(0));
  }, skip: true);
}
