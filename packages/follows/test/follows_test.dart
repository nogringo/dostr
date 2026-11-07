import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_follows/ndk_follows.dart';
import 'package:test/test.dart';

import 'mocks/fake_network.dart';

int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

void main() {
  final key0 = Bip340.generatePrivateKey();
  final key1 = Bip340.generatePrivateKey();

  late FakeRelays relays;
  late MemoryContactListCache cache;
  late Accounts accounts;
  late Follows follows;

  setUp(() {
    relays = FakeRelays();
    cache = MemoryContactListCache();
    accounts = Accounts(const Bip340EventSignerFactory());
    follows = Follows(
      query: relays.query,
      publish: relays.publish,
      cache: cache,
      accounts: accounts,
    );
  });

  tearDown(() => accounts.dispose());

  void login() => accounts.loginPrivateKey(
    pubkey: key0.publicKey,
    privkey: key0.privateKey!,
  );

  ContactList list(List<String> contacts, {required int createdAt}) =>
      ContactList(pubKey: key0.publicKey, contacts: contacts)
        ..createdAt = createdAt;

  group('getContactList', () {
    test('answers from the cache without asking relays', () async {
      await cache.saveEvent(list(['cached'], createdAt: 100).toEvent());
      relays.contactLists[key0.publicKey] = list([
        'network',
      ], createdAt: 200).toEvent();

      final contactList = await follows.getContactList(key0.publicKey);

      expect(contactList!.contacts, ['cached']);
      expect(relays.queries, 0);
    });

    test('asks relays when nothing is cached and caches the answer', () async {
      relays.contactLists[key0.publicKey] = list([
        'network',
      ], createdAt: 200).toEvent();

      final contactList = await follows.getContactList(key0.publicKey);

      expect(contactList!.contacts, ['network']);
      expect((await cache.loadContactList(key0.publicKey))!.contacts, [
        'network',
      ]);
    });

    test('forceRefresh keeps the cached list when it is newer', () async {
      await cache.saveEvent(list(['cached'], createdAt: 300).toEvent());
      relays.contactLists[key0.publicKey] = list([
        'network',
      ], createdAt: 200).toEvent();

      final contactList = await follows.getContactList(
        key0.publicKey,
        forceRefresh: true,
      );

      expect(contactList!.contacts, ['cached']);
      expect(relays.queries, 1);
    });

    test('a failed query falls back to the cached list', () async {
      await cache.saveEvent(list(['cached'], createdAt: 100).toEvent());
      relays.queryError = Exception('offline');

      final contactList = await follows.getContactList(
        key0.publicKey,
        forceRefresh: true,
      );

      expect(contactList!.contacts, ['cached']);
    });

    test('is null when no one has the list', () async {
      expect(await follows.getContactList(key1.publicKey), isNull);
    });
  });

  group('changes', () {
    test('need an account that can sign', () async {
      await expectLater(follows.broadcastAddContact('a'), throwsA(anything));

      accounts.loginPublicKey(pubkey: key1.publicKey);
      await expectLater(follows.broadcastAddContact('a'), throwsA(anything));

      expect(relays.published, isEmpty);
    });

    test('add and remove each collection', () async {
      login();
      final collections = <String, List<String> Function(ContactList)>{
        'contact': (l) => l.contacts,
        'tag': (l) => l.followedTags,
        'community': (l) => l.followedCommunities,
        'event': (l) => l.followedEvents,
      };
      final add = <String, Future<ContactList> Function(String)>{
        'contact': follows.broadcastAddContact,
        'tag': follows.broadcastAddFollowedTag,
        'community': follows.broadcastAddFollowedCommunity,
        'event': follows.broadcastAddFollowedEvent,
      };
      final remove = <String, Future<ContactList?> Function(String)>{
        'contact': follows.broadcastRemoveContact,
        'tag': follows.broadcastRemoveFollowedTag,
        'community': follows.broadcastRemoveFollowedCommunity,
        'event': follows.broadcastRemoveFollowedEvent,
      };

      for (final name in collections.keys) {
        final value = 'my-$name';
        await add[name]!(value);
        var network = ContactList.fromEvent(
          relays.contactLists[key0.publicKey]!,
        );
        expect(collections[name]!(network), contains(value), reason: name);

        await remove[name]!(value);
        network = ContactList.fromEvent(relays.contactLists[key0.publicKey]!);
        expect(collections[name]!(network), isNot(contains(value)));
        final cached = await follows.getContactList(key0.publicKey);
        expect(collections[name]!(cached!), isNot(contains(value)));
      }
    });

    test('start from the relays when the cached list is stale', () async {
      login();
      final stale = _now - Follows.kRefreshContactListDuration.inSeconds - 60;
      await cache.saveEvent(list(['old'], createdAt: stale).toEvent());
      relays.contactLists[key0.publicKey] = list([
        'old',
        'added elsewhere',
      ], createdAt: stale + 30).toEvent();

      final contactList = await follows.broadcastAddContact(key1.publicKey);

      expect(contactList.contacts, ['old', 'added elsewhere', key1.publicKey]);
    });

    test('publish nothing when the list already has the change', () async {
      login();
      await cache.saveEvent(list([key1.publicKey], createdAt: _now).toEvent());

      await follows.broadcastAddContact(key1.publicKey);
      await follows.broadcastRemoveContact('absent');

      expect(relays.published, isEmpty);
    });

    test('go to the given relays', () async {
      login();

      await follows.broadcastAddContact(
        key1.publicKey,
        customRelays: ['wss://relay.example'],
      );

      expect(relays.published.single.relays, ['wss://relay.example']);
    });

    test('are newer than a list dated in the future', () async {
      login();
      final future = _now + 1000;
      await cache.saveEvent(list([], createdAt: future).toEvent());

      await follows.broadcastAddContact(key1.publicKey);

      expect(relays.published.single.event.createdAt, future + 1);
    });

    test(
      'broadcastSetContactList publishes and caches the whole list',
      () async {
        login();

        await follows.broadcastSetContactList(list(['a', 'b'], createdAt: 1));

        final published = relays.published.single;
        expect(published.relays, isNull);
        expect(published.event.createdAt, greaterThanOrEqualTo(_now - 1));
        expect((await cache.loadContactList(key0.publicKey))!.contacts, [
          'a',
          'b',
        ]);
      },
    );
  });
}
