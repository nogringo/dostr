import 'package:ndk_url_set/ndk_url_set.dart';

Future<void> main() async {
  const pubkey =
      '82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2';

  final servers = UrlSet.fallback([
    UrlSet.blossom(pubkey),
    UrlSet.explicit(['https://blossom.primal.net']),
  ]);

  // Store this map in a queue record, resolve it later.
  final stored = servers.toMap();

  // A real lookup reads the lists from relays: this account has none.
  Future<UrlListLookup> lookup(
    String pubkey,
    UrlListKind kind,
    List<String> outboxRelays,
  ) async => const UrlListLookup.notFound();

  final resolution = await resolveUrlSet(UrlSet.fromMap(stored), lookup);
  switch (resolution) {
    case UrlsResolved(:final urls):
      print('upload to $urls');
    case UrlsUnavailable(:final reason):
      print('try again later: $reason');
  }
}
