import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_blossom/ndk_blossom.dart';
import 'package:test/test.dart';

Files _files() => Files(
  Blossom(
    accounts: Accounts(const Bip340EventSignerFactory()),
    eventSignerFactory: const Bip340EventSignerFactory(),
    getUserServerList: (_) async => null,
  ),
);

void main() async {
  test('download test - blossom', () async {
    final downloadResult = await _files().download(
      url:
          "https://cdn.hzrd149.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.pdf",
    );

    print(
      "file of type: ${downloadResult.mimeType}, size: ${downloadResult.data.length}",
    );

    expect(downloadResult.data.length, greaterThan(0));
  }, skip: true);

  test('download test - non blossom', () async {
    final downloadResult = await _files().download(
      url: "https://camelus.app/.well-known/nostr.json",
    );

    print(
      "file of type: ${downloadResult.mimeType}, size: ${downloadResult.data.length}",
    );

    expect(downloadResult.data.length, greaterThan(0));
  }, skip: true);
}
