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
}
