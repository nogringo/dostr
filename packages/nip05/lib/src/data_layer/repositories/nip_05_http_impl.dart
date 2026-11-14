import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/nip_05_defaults.dart';
import '../../domain_layer/entities/nip_05.dart';
import '../../domain_layer/repositories/nip_05_repo.dart';

/// implementation of the [Nip05Repository] interface with http
class Nip05HttpRepositoryImpl implements Nip05Repository {
  final http.Client client;

  /// how long to wait for a nostr.json response
  final Duration timeout;

  /// creates a new [Nip05HttpRepositoryImpl] instance
  Nip05HttpRepositoryImpl({
    required this.client,
    this.timeout = nip05RequestTimeout,
  });

  @override
  Future<Nip05?> fetchNip05(String nip05) async {
    final identifier = _parseIdentifier(nip05);
    if (identifier == null) {
      return null;
    }

    final json = await _getJson(identifier.url);
    if (json == null) {
      return null;
    }

    Map names = json["names"];
    Map relays = json["relays"] ?? {};

    String? pubkey = names[identifier.name];

    if (pubkey == null) {
      return null;
    }

    List<String> pRelays = [];
    if (relays[pubkey] != null) {
      pRelays = List<String>.from(relays[pubkey]);
    }

    return Nip05(
      pubKey: pubkey,
      identifier: nip05,
      valid: true,
      networkFetchTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      relays: pRelays,
    );
  }

  /// null on a 404. NIP-05 forbids redirects, so a 3xx throws like any other
  /// error status
  Future<Map<String, dynamic>?> _getJson(Uri url) async {
    final abort = Completer<void>();
    final timer = Timer(timeout, abort.complete);
    final request =
        http.AbortableRequest('GET', url, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['Accept'] = 'application/json';
    final http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(request));
    } on http.RequestAbortedException {
      throw TimeoutException('$url', timeout);
    } finally {
      timer.cancel();
    }
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'GET $url returned ${response.statusCode}',
        url,
      );
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) {
      throw FormatException('$url did not return a JSON object');
    }
    return json;
  }
}

({String name, Uri url})? _parseIdentifier(String nip05) {
  final canonical = Nip05.canonicalIdentifier(nip05);
  if (canonical == null) {
    return null;
  }
  final [name, domain] = canonical.split("@");

  final url = Uri.https(domain, "/.well-known/nostr.json", {"name": name});
  return (name: name, url: url);
}
