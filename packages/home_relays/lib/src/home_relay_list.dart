import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_url_set/dostr_url_set.dart';

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

  /// The normalized relay urls, each once.
  final List<String> candidates;
  final List<List<int>> _hashes;

  HomeRelayList(Iterable<String> relays)
    : this._(List.unmodifiable({...cleanRelayUrls(relays.toList())}));

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
  /// Throws a [FormatException] for a list of another author, since anyone
  /// can sign a forged one, or with an invalid id or signature.
  static Future<HomeRelayList> fetch({
    required EventVerifier verifier,
    String url = defaultHomeRelayListUrl,
    String author = defaultHomeRelayListAuthor,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final uri = Uri.parse(url);
    final client = http.Client();
    final Nip01Event event;
    try {
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      event =
          Nip01Event.tryFromJson(jsonDecode(utf8.decode(response.bodyBytes))) ??
          (throw FormatException('the list at $url is not a Nostr event'));
    } finally {
      client.close();
    }
    if (event.pubKey != author) {
      throw FormatException('the list at $url is not signed by $author');
    }
    if (!await verifier.verify(event)) {
      throw FormatException('the list at $url has an invalid signature');
    }
    return HomeRelayList.fromEvent(event);
  }

  /// The home relays of [pubKey] (hex): the [count] candidates closest to it,
  /// closest first, by `sha256(npub) XOR sha256(url)`.
  List<String> homeRelaysOf(String pubKey, {int count = 8}) {
    final key = _sha256(Nip19.encodePubKey(pubKey));
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
