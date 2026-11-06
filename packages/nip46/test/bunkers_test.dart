import 'dart:convert';

import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip46/ndk_nip46.dart';
import 'package:test/test.dart';

import 'mocks/mock_relay.dart';
import 'mocks/mock_remote_signer.dart';

void main() {
  group('bunker connect', () {
    late MockRelay relay;
    late MockRemoteSigner remoteSigner;
    late RelayManager relayManager;
    late Bunkers bunkers;

    String bunkerUrl() =>
        'bunker://${MockRemoteSigner.publicKey}'
        '?relay=${relay.url}&secret=s3cret';

    setUp(() async {
      relay = MockRelay();
      await relay.start();
      remoteSigner = MockRemoteSigner([relay]);

      relayManager = RelayManager(
        nostrTransportFactory: WebSocketClientNostrTransportFactory(
          pingInterval: null,
        ),
      );
      bunkers = Bunkers(
        relayReqs: RelayReqs(
          relayManager: relayManager,
          eventVerifier: Bip340EventVerifier(useIsolate: false),
        ),
        relayPublishes: RelayPublishes(relayManager: relayManager),
        eventSignerFactory: const Bip340EventSignerFactory(),
      );
    });

    tearDown(() async {
      await relayManager.closeAllTransports();
      await relay.stop();
    });

    test('sends perms and metadata', () async {
      await bunkers.connectWithBunkerUrl(
        bunkerUrl(),
        clientMetadata: const Nip46ClientMetadata(
          name: 'My app',
          url: 'https://myapp.example',
          perms: ['nip44_encrypt', 'sign_event:4'],
        ),
      );

      final params = remoteSigner.lastConnectParams!;
      expect(params, hasLength(4));
      expect(
        params.sublist(0, 3),
        equals([
          MockRemoteSigner.publicKey,
          's3cret',
          'nip44_encrypt,sign_event:4',
        ]),
      );
      expect(
        jsonDecode(params[3]),
        equals({'name': 'My app', 'url': 'https://myapp.example'}),
      );
    });

    test('sends empty perms before metadata alone', () async {
      await bunkers.connectWithBunkerUrl(
        bunkerUrl(),
        clientMetadata: const Nip46ClientMetadata(name: 'My app'),
      );

      final params = remoteSigner.lastConnectParams!;
      expect(params[2], isEmpty);
      expect(jsonDecode(params[3]), equals({'name': 'My app'}));
    });

    test('without metadata sends pubkey and secret', () async {
      await bunkers.connectWithBunkerUrl(bunkerUrl());

      expect(
        remoteSigner.lastConnectParams,
        equals([MockRemoteSigner.publicKey, 's3cret']),
      );
    });

    test(
      'connects when the remote signer accepts a nostrconnect URL',
      () async {
        final nostrConnect = bunkers.createNostrConnect(relays: [relay.url]);
        expect(
          Uri.parse(nostrConnect.nostrConnectURL).host,
          equals(nostrConnect.publicKey),
        );

        final connecting = bunkers.connectWithNostrConnect(nostrConnect);
        while (!relay.openClients.any((c) => c.subscriptions.isNotEmpty)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await remoteSigner.acceptNostrConnect(
          relay,
          nostrConnect.nostrConnectURL,
        );

        final connection = await connecting;
        expect(connection!.remotePubkey, equals(MockRemoteSigner.publicKey));
        expect(connection.privateKey, equals(nostrConnect.privateKey));
        expect(connection.relays, equals([relay.url]));
      },
    );
  });

  test('nostrconnect URL carries perms and metadata', () {
    final keyPair = Bip340.generatePrivateKey();
    final nostrConnect = NostrConnect(
      relays: ['wss://relay.example.com'],
      privateKey: keyPair.privateKey!,
      publicKey: keyPair.publicKey,
      clientMetadata: const Nip46ClientMetadata(
        name: 'My app',
        url: 'https://myapp.example',
        image: 'https://myapp.example/icon.png',
        perms: ['nip44_encrypt', 'sign_event:4'],
      ),
    );

    final query = Uri.parse(nostrConnect.nostrConnectURL).queryParameters;
    expect(query['perms'], equals('nip44_encrypt,sign_event:4'));
    expect(query['name'], equals('My app'));
    expect(query['url'], equals('https://myapp.example'));
    expect(query['image'], equals('https://myapp.example/icon.png'));
  });
}
