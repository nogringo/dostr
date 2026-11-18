import 'dart:convert';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:test/test.dart';

void main() {
  group('bunker connect', () {
    late MockRelay relay;
    late MockRemoteSigner remoteSigner;
    late RelayManager relayManager;
    late Bunkers bunkers;

    String bunkerUrl({String? secret = 's3cret'}) =>
        'bunker://${MockRemoteSigner.publicKey}'
        '?relay=${relay.url}${secret == null ? '' : '&secret=$secret'}';

    Future<void> subscribed(MockRelay relay) async {
      while (!relay.openClients.any((c) => c.subscriptions.isNotEmpty)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    setUp(() async {
      relay = MockRelay();
      await relay.start();
      remoteSigner = MockRemoteSigner([relay]);

      relayManager = RelayManager(
        nostrTransportFactory: webSocketTransportFactory(pingInterval: null),
      );
      bunkers = Bunkers(
        relayReqs: RelayReqs(
          relayManager: relayManager,
          eventVerifier: Bip340EventVerifier(),
        ),
        relayPublishes: RelayPublishes(relayManager: relayManager),
        signerFactory: const Bip340SignerFactory(),
      );
    });

    tearDown(() async {
      await relayManager.dispose();
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

    test('connects with a bunker URL without a secret', () async {
      final connection = await bunkers.connectWithBunkerUrl(
        bunkerUrl(secret: null),
      );

      expect(connection.remotePubkey, equals(MockRemoteSigner.publicKey));
      expect(
        remoteSigner.lastConnectParams,
        equals([MockRemoteSigner.publicKey]),
      );
    });

    test('sends an empty secret before perms', () async {
      await bunkers.connectWithBunkerUrl(
        bunkerUrl(secret: null),
        clientMetadata: const Nip46ClientMetadata(perms: ['sign_event:1']),
      );

      expect(
        remoteSigner.lastConnectParams,
        equals([MockRemoteSigner.publicKey, '', 'sign_event:1']),
      );
    });

    test('accepts the secret as an answer to connect', () async {
      remoteSigner.answers['connect'] = {'result': 's3cret'};

      final connection = await bunkers.connectWithBunkerUrl(bunkerUrl());

      expect(connection.remotePubkey, equals(MockRemoteSigner.publicKey));
    });

    test('a refused connect throws at once', () async {
      remoteSigner.answers['connect'] = {'error': 'denied'};

      await expectLater(
        bunkers.connectWithBunkerUrl(bunkerUrl()),
        throwsA(
          isA<SignerRequestRejectedException>().having(
            (e) => e.originalMessage,
            'originalMessage',
            'denied',
          ),
        ),
      );
    });

    test('forwards the auth challenge of connect', () async {
      const authUrl = 'https://signer.example/approve';
      remoteSigner.authUrl = authUrl;
      final challenges = <String>[];

      await bunkers.connectWithBunkerUrl(
        bunkerUrl(),
        authCallback: challenges.add,
      );

      expect(challenges, equals([authUrl]));
    });

    test('drops a connect auth challenge that is not https', () async {
      remoteSigner.authUrl = 'intent://approve#Intent;scheme=signer;end';
      final challenges = <String>[];

      await bunkers.connectWithBunkerUrl(
        bunkerUrl(),
        authCallback: challenges.add,
      );

      expect(challenges, isEmpty);
    });

    test('throws for a bunker URL without a hex pubkey', () async {
      await expectLater(
        bunkers.connectWithBunkerUrl('bunker://npub1abc?relay=${relay.url}'),
        throwsArgumentError,
      );
      expect(relay.received('EVENT'), isEmpty);
    });

    test('connect fails at once when no relay takes it', () async {
      relay.rejectEventsWith = 'blocked: not here';

      await expectLater(
        bunkers.connectWithBunkerUrl(bunkerUrl()),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('connect skips the messages it cannot read', () async {
      remoteSigner.contentsBeforeAnswer = ['not a ciphertext'];

      final connection = await bunkers.connectWithBunkerUrl(bunkerUrl());

      expect(connection.remotePubkey, equals(MockRemoteSigner.publicKey));
    });

    test('connect fails when the remote signer does not answer', () async {
      final silentRelay = MockRelay();
      await silentRelay.start();
      addTearDown(silentRelay.stop);

      await expectLater(
        bunkers.connectWithBunkerUrl(
          'bunker://${MockRemoteSigner.publicKey}?relay=${silentRelay.url}',
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<SignerRequestFailedException>()),
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
        await subscribed(relay);
        await remoteSigner.acceptNostrConnect(
          relay,
          nostrConnect.nostrConnectURL,
        );

        final connection = await connecting;
        expect(connection.remotePubkey, equals(MockRemoteSigner.publicKey));
        expect(connection.privateKey, equals(nostrConnect.privateKey));
        expect(connection.relays, equals([relay.url]));
      },
    );

    test('nostrconnect skips what it cannot read and a wrong secret', () async {
      final nostrConnect = bunkers.createNostrConnect(relays: [relay.url]);
      final stranger = Bip340.generateKeyPair();
      Nip01Event fromStranger(String content) => Bip340.signEvent(
        event: Nip01Event(
          pubkey: stranger.publicKey,
          kind: BunkerRequest.kKind,
          tags: [
            ['p', nostrConnect.publicKey],
          ],
          content: content,
        ),
        privateKey: stranger.privateKey,
      );

      final connecting = bunkers.connectWithNostrConnect(nostrConnect);
      await subscribed(relay);
      relay.publish(fromStranger('not a ciphertext'));
      relay.publish(
        fromStranger(
          await Bip340Signer(stranger.privateKey).encryptNip44(
            plaintext: jsonEncode({'id': 'x', 'result': 'wrong secret'}),
            recipientPubkey: nostrConnect.publicKey,
          ),
        ),
      );
      await remoteSigner.acceptNostrConnect(
        relay,
        nostrConnect.nostrConnectURL,
      );

      final connection = await connecting;
      expect(connection.remotePubkey, equals(MockRemoteSigner.publicKey));
    });

    test('nostrconnect fails when no remote signer accepts in time', () async {
      final nostrConnect = bunkers.createNostrConnect(relays: [relay.url]);

      await expectLater(
        bunkers.connectWithNostrConnect(
          nostrConnect,
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });
  });

  test('nostrconnect URL carries perms and metadata', () {
    final keyPair = Bip340.generateKeyPair();
    final nostrConnect = NostrConnect(
      relays: [RelayUrl.parse('wss://relay.example.com')],
      privateKey: keyPair.privateKey,
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
