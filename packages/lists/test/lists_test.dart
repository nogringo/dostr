import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_lists/ndk_lists.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:test/test.dart';

import 'mocks/fake_network.dart';

void main() {
  final key0 = Bip340.generatePrivateKey();
  final key1 = Bip340.generatePrivateKey();

  late FakeRelays relays;
  late MemoryNip51ListCache cache;
  late MemoryPlaintextCache plaintextCache;
  late Accounts accounts;
  late Lists lists;

  setUp(() {
    relays = FakeRelays();
    cache = MemoryNip51ListCache();
    plaintextCache = MemoryPlaintextCache();
    accounts = Accounts(const Bip340EventSignerFactory());
    lists = Lists(
      query: relays.query,
      publish: relays.publish,
      cache: cache,
      accounts: accounts,
      plaintextCache: plaintextCache,
    );
  });

  tearDown(() => accounts.dispose());

  void login() => accounts.loginPrivateKey(
    pubkey: key0.publicKey,
    privkey: key0.privateKey!,
  );

  Nip01Event listEvent(
    String pubKey,
    int kind,
    List<List<String>> tags, {
    required int createdAt,
  }) => Nip01Event(
    pubKey: pubKey,
    kind: kind,
    tags: tags,
    content: '',
    createdAt: createdAt,
  );

  group('lists', () {
    test('getSingleNip51List needs a logged account', () {
      expect(
        () => lists.getSingleNip51List(Nip51List.kMute),
        throwsA(isA<Exception>()),
      );
    });

    test('getSingleNip51List answers from the cache', () async {
      login();
      await cache.saveEvent(
        listEvent(key0.publicKey, Nip51List.kMute, [
          ['p', key1.publicKey],
        ], createdAt: 100),
      );

      final list = await lists.getSingleNip51List(Nip51List.kMute);

      expect(list!.pubKeys.single.value, key1.publicKey);
      expect(relays.queries, isEmpty);
    });

    test(
      'getSingleNip51List takes the newest from relays and caches it',
      () async {
        login();
        relays.events.addAll([
          listEvent(key0.publicKey, Nip51List.kMute, [
            ['word', 'old'],
          ], createdAt: 100),
          listEvent(key0.publicKey, Nip51List.kMute, [
            ['word', 'new'],
          ], createdAt: 200),
        ]);

        final list = await lists.getSingleNip51List(
          Nip51List.kMute,
          timeout: const Duration(seconds: 2),
        );

        expect(list!.words.single.value, 'new');
        expect(relays.queries.single.timeout, const Duration(seconds: 2));
        expect(relays.queries.single.cacheRead, isTrue);
        expect(cache.events, isNotEmpty);
      },
    );

    test('a private element is encrypted on publish and read back', () async {
      login();

      await lists.addElementToList(
        kind: Nip51List.kBookmarks,
        tag: Nip51List.kThread,
        value: 'secret-event',
        private: true,
        broadcastRelays: ['wss://relay.example.com'],
      );

      final published = relays.published.single;
      expect(published.relays, ['wss://relay.example.com']);
      expect(published.event.tags, isEmpty);
      expect(published.event.content, isNot(contains('secret-event')));

      final list = await lists.getSingleNip51List(
        Nip51List.kBookmarks,
        forceRefresh: true,
      );
      expect(list!.threads.single.value, 'secret-event');
      expect(list.threads.single.private, isTrue);
    });

    test(
      'private elements are decrypted once with a plaintext cache',
      () async {
        login();
        await lists.addElementToList(
          kind: Nip51List.kBookmarks,
          tag: Nip51List.kThread,
          value: 'secret-event',
          private: true,
        );

        await lists.getSingleNip51List(Nip51List.kBookmarks);
        await lists.getSingleNip51List(Nip51List.kBookmarks);

        expect(plaintextCache.decryptions, 1);
      },
    );

    test('getPublicList leaves the private elements out', () async {
      login();
      await lists.addElementToList(
        kind: Nip51List.kBookmarks,
        tag: Nip51List.kThread,
        value: 'public-event',
      );
      await lists.addElementToList(
        kind: Nip51List.kBookmarks,
        tag: Nip51List.kThread,
        value: 'secret-event',
        private: true,
      );

      final list = await lists.getPublicList(
        kind: Nip51List.kBookmarks,
        publicKey: key0.publicKey,
        forceRefresh: true,
      );

      expect(list!.threads.map((e) => e.value), ['public-event']);
    });

    test('removeElementFromList publishes the list without it', () async {
      login();
      await lists.addElementToList(
        kind: Nip51List.kMute,
        tag: Nip51List.kPubkey,
        value: key1.publicKey,
      );

      final list = await lists.removeElementFromList(
        kind: Nip51List.kMute,
        tag: Nip51List.kPubkey,
        value: key1.publicKey,
      );

      expect(list!.pubKeys, isEmpty);
      expect(relays.published.last.event.tags, isEmpty);
    });
  });

  group('sets', () {
    test('addElementToSet creates the set and getSetByName finds it', () async {
      login();

      await lists.addElementToSet(
        name: 'favorites',
        tag: Nip51List.kRelay,
        value: 'wss://relay.example.com',
        kind: Nip51List.kRelaySet,
      );

      final event = relays.published.single.event;
      expect(event.dTag, 'favorites');
      expect(event.kind, Nip51List.kRelaySet);

      final set = await lists.getSetByName(
        name: 'favorites',
        kind: Nip51List.kRelaySet,
        forceRefresh: true,
      );
      expect(set!.allRelays, ['wss://relay.example.com']);
    });

    test('deleteSet publishes a deletion and empties the cache', () async {
      login();
      final set = await lists.addElementToSet(
        name: 'favorites',
        tag: Nip51List.kRelay,
        value: 'wss://relay.example.com',
        kind: Nip51List.kRelaySet,
      );
      final setEvent = relays.published.single.event;

      await lists.deleteSet(name: set!.name, kind: Nip51List.kRelaySet);

      final deletion = relays.published.last.event;
      expect(deletion.kind, 5);
      expect(deletion.pubKey, key0.publicKey);
      expect(deletion.tags, [
        ['e', setEvent.id],
      ]);
      expect(cache.events.where((e) => e.kind == Nip51List.kRelaySet), isEmpty);
    });

    test('getPublicSets streams the sets of a pubkey', () async {
      relays.events.add(
        listEvent(key1.publicKey, Nip51List.kFollowSet, [
          ['d', 'friends'],
          ['p', key0.publicKey],
        ], createdAt: 100),
      );

      final sets = await lists
          .getPublicSets(kind: Nip51List.kFollowSet, publicKey: key1.publicKey)
          .last;

      expect(sets!.single.name, 'friends');
      expect(sets.single.pubKeys.single.value, key0.publicKey);
    });

    test('getPublicSets emits an empty list when there is no set', () async {
      final sets = await lists
          .getPublicSets(kind: Nip51List.kFollowSet, publicKey: key1.publicKey)
          .toList();

      expect(sets.single, isEmpty);
    });
  });
}
