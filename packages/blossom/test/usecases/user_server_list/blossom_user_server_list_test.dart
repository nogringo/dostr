import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_blossom/dostr_blossom.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:test/test.dart';

void main() {
  late Accounts accounts;
  late List<Nip01Event> relayEvents;
  late List<({List<String> authors, int kind, Duration timeout})> queries;
  late List<Nip01Event> published;
  late BlossomUserServerList<
    List<({String relayUrl, bool broadcastSuccessful})>
  >
  serverList;

  setUp(() {
    accounts = Accounts(const Bip340SignerFactory());
    relayEvents = [];
    queries = [];
    published = [];
    serverList = BlossomUserServerList(
      query: ({required authors, required kind, required timeout}) async {
        queries.add((authors: authors, kind: kind, timeout: timeout));
        return relayEvents;
      },
      publish: (event) async {
        published.add(event);
        return [(relayUrl: 'wss://relay.example', broadcastSuccessful: true)];
      },
      accounts: accounts,
    );
  });

  Nip01Event listOf(List<String> servers, {required int createdAt}) =>
      Nip01Event(
        pubkey: 'alice',
        kind: BlossomUserServerList.kBlossomUserServerList,
        tags: [
          for (final server in servers) ['server', server],
        ],
        content: '',
        createdAt: createdAt,
      );

  group('getUserServerList', () {
    test('reads the servers of the newest list, in order', () async {
      relayEvents.addAll([
        listOf(['https://old.example'], createdAt: 1),
        listOf(['https://b.example', 'https://a.example'], createdAt: 2),
      ]);

      expect(await serverList.getUserServerList(pubkeys: ['alice']), [
        'https://b.example',
        'https://a.example',
      ]);
      expect(queries.single.authors, ['alice']);
      expect(queries.single.kind, BlossomUserServerList.kBlossomUserServerList);
    });

    test('normalizes the servers, each once, and drops the others', () async {
      relayEvents.add(
        listOf([
          'HTTPS://B.example:443/',
          'wss://relay.example',
          'https://cdn.example@evil.example',
          'https://b.example',
          'https://a.example',
        ], createdAt: 1),
      );

      expect(await serverList.getUserServerList(pubkeys: ['alice']), [
        'https://b.example',
        'https://a.example',
      ]);
    });

    test('returns null when the user has no list', () async {
      expect(await serverList.getUserServerList(pubkeys: ['alice']), isNull);
    });
  });

  group('publishUserServerList', () {
    test('publishes the list of the logged account, in order', () async {
      final key = Bip340.generateKeyPair();
      accounts.loginPrivateKey(privkey: key.privateKey);

      final responses = await serverList.publishUserServerList(
        serverUrlsOrdered: ['https://b.example', 'https://a.example'],
      );

      expect(responses.single.broadcastSuccessful, isTrue);
      final event = published.single;
      expect(event.pubkey, key.publicKey);
      expect(event.kind, BlossomUserServerList.kBlossomUserServerList);
      expect(event.tags, [
        ['server', 'https://b.example'],
        ['server', 'https://a.example'],
      ]);
    });

    test('publishes the urls normalized, each once', () async {
      accounts.loginPrivateKey(privkey: Bip340.generateKeyPair().privateKey);

      await serverList.publishUserServerList(
        serverUrlsOrdered: [
          'HTTPS://B.example:443/',
          'https://a.example',
          'https://b.example',
        ],
      );

      expect(published.single.tags, [
        ['server', 'https://b.example'],
        ['server', 'https://a.example'],
      ]);
    });

    test('throws on a url that is not a server url', () async {
      accounts.loginPrivateKey(privkey: Bip340.generateKeyPair().privateKey);

      await expectLater(
        serverList.publishUserServerList(
          serverUrlsOrdered: ['https://a.example', 'wss://relay.example'],
        ),
        throwsFormatException,
      );
      expect(published, isEmpty);
    });

    test('throws without a logged account', () async {
      await expectLater(
        serverList.publishUserServerList(
          serverUrlsOrdered: ['https://a.example'],
        ),
        throwsA('Not logged in'),
      );
      expect(published, isEmpty);
    });

    test('throws on an empty list', () async {
      await expectLater(
        serverList.publishUserServerList(serverUrlsOrdered: []),
        throwsA(isA<Exception>()),
      );
      expect(published, isEmpty);
    });
  });
}
