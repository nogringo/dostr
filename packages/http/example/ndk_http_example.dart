import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:ndk_http/ndk_http.dart';

/// Looks up the pubkey behind a NIP-05 identifier such as `bob@example.com`.
Future<String?> nip05Pubkey(String name, String domain) async {
  final client = http.Client();
  try {
    final json = await HttpRequestDS(client).jsonRequest(
      url: Uri.https(domain, '/.well-known/nostr.json', {'name': name}),
      followRedirects: false,
      timeout: const Duration(seconds: 5),
    );
    final names = json['names'];
    final pubkey = names is Map ? names[name] : null;
    return pubkey is String ? pubkey : null;
  } on http.ClientException {
    // a non-2xx status (HttpRequestException) or no response at all
    return null;
  } on TimeoutException {
    return null;
  } on FormatException {
    return null;
  } finally {
    client.close();
  }
}
