import 'dart:async';
import 'dart:convert';

import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:http/http.dart' as http;

import '../../config/nip_05_defaults.dart';
import '../../domain_layer/entities/nip_05.dart';
import '../../domain_layer/repositories/nip_05_repository.dart';

final _hexPubkey = RegExp(r'^[0-9a-fA-F]{64}$');

/// implementation of the [Nip05Repository] interface with http
class HttpNip05Repository implements Nip05Repository {
  final http.Client client;

  /// how long to wait for a nostr.json response
  final Duration timeout;

  /// creates a new [HttpNip05Repository] instance
  HttpNip05Repository({
    required this.client,
    this.timeout = nip05RequestTimeout,
  });

  @override
  Future<Nip05?> fetchNip05(
    String identifier, {
    Future<void>? abortTrigger,
  }) async {
    final canonical = Nip05.canonicalIdentifier(identifier);
    if (canonical == null) {
      return null;
    }
    final [name, domain] = canonical.split('@');

    final json = await _getJson(
      Uri.https(domain, '/.well-known/nostr.json', {'name': name}),
      abortTrigger,
    );
    if (json == null) {
      return null;
    }

    final names = json['names'];
    if (names is! Map) {
      throw const FormatException('names is not an object');
    }
    final pubkey = _entryOf(names, name);
    if (pubkey == null) {
      return null;
    }
    if (pubkey is! String || !_hexPubkey.hasMatch(pubkey)) {
      throw FormatException('names.$name is not a hex pubkey', '$pubkey');
    }

    return Nip05(
      identifier: canonical,
      pubkey: pubkey.toLowerCase(),
      relays: _relaysOf(json['relays'], pubkey),
    );
  }

  /// null on a 404. NIP-05 forbids redirects, so a 3xx throws like any other
  /// error status
  Future<Map<String, dynamic>?> _getJson(
    Uri url,
    Future<void>? abortTrigger,
  ) async {
    final abort = Completer<void>();
    var timedOut = false;
    final timer = Timer(timeout, () {
      if (abort.isCompleted) return;
      timedOut = true;
      abort.complete();
    });
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    unawaited(abortTrigger?.then((_) => stop(), onError: (Object _) => stop()));
    final request =
        http.AbortableRequest('GET', url, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['Accept'] = 'application/json';
    final http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(request));
    } on http.RequestAbortedException {
      if (timedOut) throw TimeoutException('$url', timeout);
      rethrow;
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

/// NIP-05 names are case-insensitive, so another case is a fallback for
/// [name], which is lowercase
Object? _entryOf(Map names, String name) {
  if (names.containsKey(name)) return names[name];
  for (final MapEntry(:key, :value) in names.entries) {
    if (key is String && key.toLowerCase() == name) return value;
  }
  return null;
}

/// NIP-05 makes the relays optional, so a missing or mistyped entry gives none
List<RelayUrl> _relaysOf(Object? relays, String pubkey) {
  final urls = relays is Map ? relays[pubkey] : null;
  if (urls is! List) return const [];
  return {
    for (final url in urls)
      if (url is String) ?RelayUrl.tryParse(url),
  }.toList();
}
