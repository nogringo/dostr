import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip19/ndk_nip19.dart';

const int _kind = 36205;
const String _name = 'home-relays';

/// Where nmail.li serves its `home-relays` list.
const String defaultHomeRelayListUrl = 'https://home-relays.nmail.li/list.json';

/// A `home-relays` list, from which every client computes the same home
/// relays for a user, as the Computed Home Relays NIP describes.
class HomeRelayList {
  /// The normalized relay urls, each once.
  final List<String> candidates;
  final List<List<int>> _hashes;

  HomeRelayList(Iterable<String> relays)
    : this._(List.unmodifiable({...cleanRelayUrls(relays.toList())}));

  HomeRelayList._(this.candidates)
    : _hashes = [for (final url in candidates) _sha256(url)];

  /// The `relay` tags of [event], a `kind:36205` named `home-relays`.
  factory HomeRelayList.fromEvent(Nip01Event event) {
    if (event.kind != _kind || event.getDtag() != _name) {
      throw ArgumentError.value(event.id, 'event', 'is not a home-relays list');
    }
    return HomeRelayList([
      for (final tag in event.tags)
        if (tag.length > 1 && tag[0] == 'relay') tag[1],
    ]);
  }

  /// Loads the list event served as JSON at [url].
  static Future<HomeRelayList> fetch({
    String url = defaultHomeRelayListUrl,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final uri = Uri.parse(url);
    final client = http.Client();
    try {
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      return HomeRelayList.fromEvent(Nip01EventModel.fromJson(json));
    } finally {
      client.close();
    }
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
