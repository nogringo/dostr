import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:http/http.dart' as http;

import 'hex_pubkey.dart';
import 'nip_05.dart';
import 'nip_05_defaults.dart';
import 'nip_05_repository.dart';

/// implementation of the [Nip05Repository] interface with http
class HttpNip05Repository implements Nip05Repository {
  final http.Client client;

  /// how long to wait for a nostr.json response, even from a [client] that
  /// cannot abort a request
  final Duration timeout;

  /// the largest body read, in bytes. A larger one throws a [FormatException]
  final int maxResponseBytes;

  /// creates a new [HttpNip05Repository] instance
  HttpNip05Repository({
    required this.client,
    this.timeout = nip05RequestTimeout,
    this.maxResponseBytes = nip05MaxResponseBytes,
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
    if (pubkey is! String || !hexPubkey.hasMatch(pubkey)) {
      throw FormatException('names.$name is not a hex pubkey', '$pubkey');
    }

    return Nip05(
      identifier: canonical,
      pubkey: pubkey.toLowerCase(),
      relays: _relaysOf(json['relays'], pubkey),
    );
  }

  /// null on a 404. NIP-05 forbids redirects, so a 3xx throws a
  /// [FormatException]
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
    final Uint8List? body;
    try {
      // some clients ignore the abortTrigger, and the timeout holds with them
      body = await Future.any([
        _send(request),
        abort.future.then((_) => throw http.RequestAbortedException(url)),
      ]);
    } on http.RequestAbortedException {
      if (timedOut) throw TimeoutException('$url', timeout);
      rethrow;
    } finally {
      timer.cancel();
    }
    if (body == null) {
      return null;
    }
    final json = jsonDecode(utf8.decode(body));
    if (json is! Map<String, dynamic>) {
      throw FormatException('$url did not return a JSON object');
    }
    return json;
  }

  /// the body, or null on a 404
  Future<Uint8List?> _send(http.BaseRequest request) async {
    final url = request.url;
    final response = await client.send(request);
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      response.stream.listen(null).cancel().ignore();
      if (status == 404) {
        return null;
      }
      if (status < 400) {
        throw FormatException('GET $url redirects ($status)');
      }
      throw http.ClientException('GET $url returned $status', url);
    }
    return _read(response.stream, url);
  }

  // not an `await for`: on DDC, leaving one escapes the fake async zone of
  // testWidgets, so pump never ends the read
  Future<Uint8List> _read(Stream<List<int>> stream, Uri url) {
    final body = BytesBuilder(copy: false);
    final read = Completer<Uint8List>();
    late final StreamSubscription<List<int>> subscription;
    subscription = stream.listen(
      (chunk) {
        body.add(chunk);
        if (body.length > maxResponseBytes) {
          subscription.cancel().ignore();
          read.completeError(
            FormatException('$url is larger than $maxResponseBytes bytes'),
          );
        }
      },
      onError: read.completeError,
      onDone: () => read.complete(body.takeBytes()),
      cancelOnError: true,
    );
    return read.future;
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
