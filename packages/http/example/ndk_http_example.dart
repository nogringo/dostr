import 'package:http/http.dart' as http;
import 'package:ndk_http/ndk_http.dart';

/// Looks up the pubkey behind a NIP-05 identifier such as `bob@example.com`.
Future<String?> nip05Pubkey(String name, String domain) async {
  final ds = HttpRequestDS(http.Client());
  try {
    final json = await ds.jsonRequest(
      'https://$domain/.well-known/nostr.json?name=$name',
      timeout: const Duration(seconds: 5),
    );
    return (json['names'] as Map<String, dynamic>?)?[name] as String?;
  } on HttpRequestException {
    return null;
  }
}
