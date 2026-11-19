import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:http/http.dart' as http;

/// Where nmail.li serves its `home-relays` list.
const String defaultHomeRelayListUrl = 'https://home-relays.nmail.li/list.json';

/// The key nmail.li signs its `home-relays` list with.
const String defaultHomeRelayListAuthor =
    '7ecce29a3f482cccff9ca19432051af9b074939121ee414ef3d09135d79c5fad';

/// A `home-relays` list, from which every client computes the same home
/// relays for a user, as the Computed Home Relays NIP describes.
class HomeRelayList {
  static const int kind = 36205;
  static const String dTag = 'home-relays';

  /// The relay urls, each once.
  final List<RelayUrl> candidates;
  final List<List<int>> _hashes;

  HomeRelayList(Iterable<String> relays)
    : this._(
        List.unmodifiable({for (final url in relays) ?RelayUrl.tryParse(url)}),
      );

  HomeRelayList._(this.candidates)
    : _hashes = [for (final url in candidates) _sha256(url)];

  /// The `relay` tags of [event], a `kind:36205` named `home-relays`.
  factory HomeRelayList.fromEvent(Nip01Event event) {
    if (event.kind != kind || event.dTag != dTag) {
      throw ArgumentError.value(event.id, 'event', 'is not a home-relays list');
    }
    return HomeRelayList([
      for (final tag in event.tags)
        if (tag.length > 1 && tag[0] == 'relay') tag[1],
    ]);
  }

  /// Loads the list event served as JSON at [url], once [verifier] checked it
  /// is signed by [author] (hex).
  ///
  /// The request goes through [client], which stays open, or through a client
  /// of its own when none is given.
  ///
  /// Throws a [TimeoutException] past [timeout], which covers the whole
  /// response and aborts the request, so it does not hold a socket of
  /// [client]. It holds with a client that ignores `abortTrigger` too, which
  /// then keeps its socket.
  ///
  /// Throws a [FormatException] for a list of another author, since anyone
  /// can sign a forged one, or with an invalid id or signature.
  static Future<HomeRelayList> fetch({
    required EventVerifier verifier,
    String url = defaultHomeRelayListUrl,
    String author = defaultHomeRelayListAuthor,
    Duration timeout = const Duration(seconds: 5),
    http.Client? client,
  }) async {
    final uri = Uri.parse(url);
    final httpClient = client ?? http.Client();
    final abort = Completer<void>();
    final timer = Timer(timeout, abort.complete);
    final request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abort.future,
    );
    final Nip01Event event;
    try {
      final (statusCode, body) = await _send(httpClient, request, abort.future);
      if (statusCode != 200) {
        throw http.ClientException('HTTP $statusCode', uri);
      }
      event =
          Nip01Event.tryFromJson(jsonDecode(utf8.decode(body))) ??
          (throw FormatException('the list at $url is not a Nostr event'));
    } on http.RequestAbortedException {
      if (abort.isCompleted) throw TimeoutException('$uri', timeout);
      rethrow;
    } finally {
      timer.cancel();
      if (client == null) httpClient.close();
    }
    if (event.pubkey != author) {
      throw FormatException('the list at $url is not signed by $author');
    }
    if (!await verifier.verify(event)) {
      throw FormatException('the list at $url has an invalid signature');
    }
    return HomeRelayList.fromEvent(event);
  }

  /// The status and body of the response to [request], or a
  /// [http.RequestAbortedException] once [abort] completes, from a client
  /// that ignores it too.
  static Future<(int, Uint8List)> _send(
    http.Client client,
    http.BaseRequest request,
    Future<void> abort,
  ) {
    final result = Completer<(int, Uint8List)>();
    void fail(Object error, StackTrace stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }

    StreamSubscription<List<int>>? body;
    unawaited(
      abort.then((_) {
        body?.cancel().ignore();
        fail(http.RequestAbortedException(request.url), StackTrace.current);
      }),
    );
    unawaited(
      client.send(request).then((response) {
        if (result.isCompleted) {
          response.stream.listen(null).cancel().ignore();
          return;
        }
        final bytes = BytesBuilder(copy: false);
        body = response.stream.listen(
          bytes.add,
          onError: fail,
          onDone: () {
            if (!result.isCompleted) {
              result.complete((response.statusCode, bytes.takeBytes()));
            }
          },
          cancelOnError: true,
        );
      }, onError: fail),
    );
    return result.future;
  }

  /// The home relays of [pubkey] (hex): the [count] candidates closest to it,
  /// closest first, by `sha256(npub) XOR sha256(url)`.
  List<RelayUrl> homeRelaysOf(String pubkey, {int count = 8}) {
    final key = _sha256(Npub(pubkey).encode());
    final distances = [
      for (final hash in _hashes)
        [for (var i = 0; i < hash.length; i++) hash[i] ^ key[i]],
    ];
    final order = List.generate(candidates.length, (i) => i)
      ..sort((a, b) => _compare(distances[a], distances[b]));
    return [for (final i in order.take(count)) candidates[i]];
  }

  static List<int> _sha256(String text) =>
      sha256.convert(utf8.encode(text)).bytes;

  /// Big-endian, so the order of the 256-bit integers.
  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return 0;
  }
}
