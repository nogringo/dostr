import 'dart:convert';

import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_user_relay_lists/ndk_user_relay_lists.dart';
import 'package:test/test.dart';

/// Relays holding [events], recording what is asked and published.
class FakeRelays {
  final List<Nip01Event> events = [];
  final List<({String name, Iterable<String>? relays})> queries = [];
  final List<({Nip01Event event, List<String> relays})> published = [];

  Stream<Nip01Event> query(
    Filter filter, {
    required String name,
    Iterable<String>? relays,
  }) {
    queries.add((name: name, relays: relays));
    return Stream.fromIterable(
      events.where(
        (e) =>
            (filter.authors?.contains(e.pubKey) ?? true) &&
            (filter.kinds?.contains(e.kind) ?? true),
      ),
    );
  }

  Future<void> publish(
    Nip01Event event, {
    required Iterable<String> relays,
  }) async => published.add((event: event, relays: relays.toList()));
}

void main() {
  const alice = 'alice';
  late FakeRelays relays;
  late MemCacheManager cache;
  late Accounts accounts;
  late UserRelayLists userRelayLists;

  setUp(() {
    relays = FakeRelays();
    cache = MemCacheManager();
    accounts = Accounts(const Bip340EventSignerFactory());
    userRelayLists = UserRelayLists(
      query: relays.query,
      publish: relays.publish,
      cacheManager: cache,
      accounts: accounts,
    );
  });

  group('getSingleUserRelayList', () {
    test('reads a NIP-65 from the relays and caches it', () async {
      relays.events.add(
        Nip65.fromMap(alice, {
          'wss://read.example': ReadWriteMarker.readOnly,
          'wss://write.example': ReadWriteMarker.writeOnly,
        }).toEvent(),
      );

      final list = await userRelayLists.getSingleUserRelayList(alice);

      expect(list!.relays, {
        'wss://read.example': ReadWriteMarker.readOnly,
        'wss://write.example': ReadWriteMarker.writeOnly,
      });
      expect(relays.queries.single.name, 'user-relay-lists');

      await userRelayLists.getSingleUserRelayList(alice);
      expect(relays.queries, hasLength(1));
    });

    test('falls back to the relays of a NIP-02 contact list', () async {
      relays.events.add(
        Nip01Event(
          pubKey: alice,
          kind: Nip01Event.kContactListKind,
          tags: const [],
          content: jsonEncode({
            'wss://old.example': {'read': true, 'write': true},
          }),
        ),
      );

      final list = await userRelayLists.getSingleUserRelayList(alice);

      expect(list!.relays, {'wss://old.example': ReadWriteMarker.readWrite});
    });

    test('returns null when the user has no relay list', () async {
      expect(await userRelayLists.getSingleUserRelayList(alice), isNull);
    });
  });

  group('getDmRelays', () {
    Nip01Event dmRelays(List<String> urls) => Nip01Event(
      pubKey: alice,
      kind: Nip01Event.kDmRelayListKind,
      tags: [
        for (final url in urls) ['relay', url],
      ],
      content: '',
    );

    test('asks the discovery relays, then answers from the cache', () async {
      relays.events.add(dmRelays(['wss://dm.example']));

      expect(
        await userRelayLists.getDmRelays(
          alice,
          discoveryRelays: ['wss://discovery.example'],
        ),
        ['wss://dm.example'],
      );
      expect(relays.queries.single.name, 'dm-relays');
      expect(relays.queries.single.relays, ['wss://discovery.example']);

      expect(await userRelayLists.getDmRelays(alice), ['wss://dm.example']);
      expect(relays.queries, hasLength(1));
    });

    test('returns null when the user has none', () async {
      expect(await userRelayLists.getDmRelays(alice), isNull);
    });
  });

  group('editing the relay list of the logged account', () {
    late KeyPair key;

    setUp(() {
      key = Bip340.generatePrivateKey();
      accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
    });

    test(
      'broadcastAddNip65Relay publishes the list to the given relays',
      () async {
        final list = await userRelayLists.broadcastAddNip65Relay(
          relayUrl: 'wss://new.example',
          marker: ReadWriteMarker.writeOnly,
          broadcastRelays: ['wss://broadcast.example'],
        );

        expect(list.pubKey, key.publicKey);
        expect(list.relays, {
          'wss://broadcast.example': ReadWriteMarker.readWrite,
          'wss://new.example': ReadWriteMarker.writeOnly,
        });
        final published = relays.published.single;
        expect(published.relays, ['wss://broadcast.example']);
        expect(published.event.kind, Nip65.kKind);
        expect(published.event.pubKey, key.publicKey);
        expect(
          (await cache.loadUserRelayList(key.publicKey))!.relays,
          list.relays,
        );
      },
    );

    test('setInitialUserRelayList publishes to the relays it lists', () async {
      final now = Nip01Event.secondsSinceEpoch();
      await userRelayLists.setInitialUserRelayList(
        UserRelayList(
          pubKey: key.publicKey,
          relays: {'wss://mine.example': ReadWriteMarker.readWrite},
          createdAt: now,
          refreshedTimestamp: now,
        ),
      );

      expect(relays.published.single.relays, ['wss://mine.example']);
    });

    test('broadcastRemoveNip65Relay throws without a relay list', () async {
      await expectLater(
        userRelayLists.broadcastRemoveNip65Relay(
          relayUrl: 'wss://new.example',
          broadcastRelays: ['wss://broadcast.example'],
        ),
        throwsA(contains('no user relay list found')),
      );
      expect(relays.published, isEmpty);
    });
  });

  test('editing throws without a logged account', () async {
    await expectLater(
      userRelayLists.broadcastAddNip65Relay(
        relayUrl: 'wss://new.example',
        marker: ReadWriteMarker.readWrite,
        broadcastRelays: ['wss://broadcast.example'],
      ),
      throwsA('cannot sign without a signer'),
    );
    expect(relays.published, isEmpty);
  });
}
