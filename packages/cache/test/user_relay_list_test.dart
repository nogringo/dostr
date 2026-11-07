import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_follows/ndk_follows.dart';
import 'package:ndk_cache/ndk_cache.dart';

import 'package:test/test.dart';

void main() {
  group('Nip02', () {
    test('relaysFromNip02Content', () {
      final event = Nip01Event(
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        pubKey: 'pubkeyUser1',
        kind: ContactList.kKind,
        content:
            "{\"wss://relay.ditto.pub\":{\"read\":true,\"write\":true},\"wss://relay.primal.net\":{\"read\":true,\"write\":true}}",
        tags: [
          ['p', 'contact1'],
        ],
      );
      expect(UserRelayList.relaysFromNip02Content(event), {
        "wss://relay.ditto.pub": ReadWriteMarker.readWrite,
        "wss://relay.primal.net": ReadWriteMarker.readWrite,
      });
    });
  });

  group('loadLatest', () {
    UserRelayList relayList(String pubKey, String url) => UserRelayList(
      pubKey: pubKey,
      relays: {url: ReadWriteMarker.readWrite},
      createdAt: 1,
      refreshedTimestamp: 1,
    );

    test('loads one list per pubkey, skipping pubkeys without one', () async {
      final cache = MemCacheManager();
      await cache.saveUserRelayLists([
        relayList('a', 'wss://a.example'),
        relayList('b', 'wss://b.example'),
      ]);

      final lists = await UserRelayList.loadLatest(cache, ['a', 'b', 'c', 'a']);

      expect(lists.map((list) => list.pubKey), ['b', 'a']);
    });
  });
}
