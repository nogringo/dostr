import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_home_relays/ndk_home_relays.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_nip19/ndk_nip19.dart';
import 'package:test/test.dart';

Nip01Event list(List<List<String>> tags) => Nip01Event(
  pubKey: 'a' * 64,
  kind: 36205,
  tags: tags,
  content: '',
  createdAt: 1000,
);

/// Serves [body] with [status] on every path, until the test ends.
Future<String> serve(String body, {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) {
    request.response
      ..statusCode = status
      ..write(body)
      ..close();
  });
  return 'http://127.0.0.1:${server.port}/list.json';
}

void main() {
  test('computes the home relays of the NIP example', () {
    final list = HomeRelayList([
      'wss://indexer.coracle.social',
      'wss://nostr-pub.wellorder.net',
      'wss://nostr.bitcoiner.social',
      'wss://nostr.data.haus',
      'wss://nostr.oxtr.dev',
      'wss://offchain.pub',
      'wss://purplepag.es',
      'wss://relay.angor.io',
      'wss://relay.coinos.io',
      'wss://relay.ditto.pub',
      'wss://relay.nos.social',
      'wss://relay.nostr.net',
      'wss://relay.nostrplebs.com',
      'wss://relay.primal.net',
      'wss://user.kindpag.es',
      'wss://yabu.me',
    ]);
    final pubKey = Nip19.decode(
      'npub1jlp4rzsraw0nvvuyavgf2z497juw7y44v40ch23lnwzlnre3wuusjhmu65',
    );

    expect(list.homeRelaysOf(pubKey), [
      'wss://relay.angor.io',
      'wss://relay.primal.net',
      'wss://yabu.me',
      'wss://relay.ditto.pub',
      'wss://purplepag.es',
      'wss://relay.coinos.io',
      'wss://nostr.data.haus',
      'wss://indexer.coracle.social',
    ]);
  });

  test('gives every candidate when there are fewer than count', () {
    final list = HomeRelayList(['wss://a.example.com', 'wss://b.example.com']);

    expect(
      list.homeRelaysOf('a' * 64),
      unorderedEquals(['wss://a.example.com', 'wss://b.example.com']),
    );
    expect(list.homeRelaysOf('a' * 64, count: 1), hasLength(1));
  });

  test('normalizes the candidates and keeps each once', () {
    final list = HomeRelayList([
      'wss://Relay.Example.com/',
      'wss://relay.example.com',
      'https://relay.example.com',
    ]);

    expect(list.candidates, ['wss://relay.example.com']);
  });

  test('reads the relay tags of a home-relays list', () {
    final homeRelays = HomeRelayList.fromEvent(
      list([
        ['d', 'home-relays'],
        ['relay', 'wss://a.example.com'],
        ['r', 'wss://b.example.com'],
      ]),
    );

    expect(homeRelays.candidates, ['wss://a.example.com']);
  });

  test('rejects another list', () {
    final other = list([
      ['d', 'other'],
      ['relay', 'wss://a.example.com'],
    ]);

    expect(() => HomeRelayList.fromEvent(other), throwsArgumentError);
  });

  group('fetch', () {
    final verifier = Bip340EventVerifier();
    final author = Bip340.generatePrivateKey();
    final other = Bip340.generatePrivateKey();

    Nip01Event listEvent(String pubKey, KeyPair signer) => Bip340.signEvent(
      event: Nip01Event(
        pubKey: pubKey,
        kind: 36205,
        tags: [
          ['d', 'home-relays'],
          ['relay', 'wss://a.example.com'],
        ],
        content: '',
      ),
      privateKey: signer.privateKey!,
    );

    Future<HomeRelayList> fetch(Nip01Event event) async => HomeRelayList.fetch(
      verifier: verifier,
      url: await serve(jsonEncode(event.toJson())),
      author: author.publicKey,
    );

    test('loads the list its author signed', () async {
      final list = await fetch(listEvent(author.publicKey, author));

      expect(list.candidates, ['wss://a.example.com']);
    });

    test('rejects a list of another author', () {
      expect(fetch(listEvent(other.publicKey, other)), throwsFormatException);
    });

    test('rejects a signature from another key', () {
      expect(fetch(listEvent(author.publicKey, other)), throwsFormatException);
    });

    test('rejects a list changed after it was signed', () {
      final signed = listEvent(author.publicKey, author);
      final changed = Nip01Event(
        id: signed.id,
        sig: signed.sig,
        pubKey: signed.pubKey,
        createdAt: signed.createdAt,
        kind: signed.kind,
        tags: [
          ...signed.tags,
          ['relay', 'wss://b.example.com'],
        ],
        content: signed.content,
      );

      expect(fetch(changed), throwsFormatException);
    });

    test('rejects a body that is not an event', () async {
      final url = await serve('{"hello": "world"}');

      expect(
        HomeRelayList.fetch(verifier: verifier, url: url),
        throwsFormatException,
      );
    });

    test('fails on an HTTP error', () async {
      final url = await serve('', status: 404);

      expect(
        HomeRelayList.fetch(verifier: verifier, url: url),
        throwsA(isA<http.ClientException>()),
      );
    });
  });
}
