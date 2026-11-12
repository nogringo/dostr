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
    accounts = Accounts(const Bip340EventSignerFactory());
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
        pubKey: 'alice',
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

    test('returns null when the user has no list', () async {
      expect(await serverList.getUserServerList(pubkeys: ['alice']), isNull);
    });
  });

  group('publishUserServerList', () {
    test('publishes the list of the logged account, in order', () async {
      final key = Bip340.generatePrivateKey();
      accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);

      final responses = await serverList.publishUserServerList(
        serverUrlsOrdered: ['https://b.example', 'https://a.example'],
      );

      expect(responses.single.broadcastSuccessful, isTrue);
      final event = published.single;
      expect(event.pubKey, key.publicKey);
      expect(event.kind, BlossomUserServerList.kBlossomUserServerList);
      expect(event.tags, [
        ['server', 'https://b.example'],
        ['server', 'https://a.example'],
      ]);
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
