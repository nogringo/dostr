import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk/domain_layer/entities/contact_list.dart';
import 'package:ndk/domain_layer/entities/read_write_marker.dart';

import 'package:test/test.dart';

void main() {
  group('Nip02', () {
    test('fromEvent', () {
      final event = Nip01Event(
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        pubKey: 'pubkeyUser1',
        kind: ContactList.kKind,
        content:
            "{\"wss://relay.ditto.pub\":{\"read\":true,\"write\":true},\"wss://relay.primal.net\":{\"read\":true,\"write\":true}}",
        tags: [
          ['p', 'contact1'],
          ['p', 'contact2'],
          ['p', 'contact3'],
          ['p', 'contact4', 'wss://relay.com', 'petname'],
          ['invalid'],
        ],
      );
      final nip02 = ContactList.fromEvent(event);
      expect(nip02.contacts, ['contact1', 'contact2', 'contact3', 'contact4']);
      expect(ContactList.relaysFromContent(event), {
        "wss://relay.ditto.pub": ReadWriteMarker.readWrite,
        "wss://relay.primal.net": ReadWriteMarker.readWrite,
      });
    });

    test('toEvent', () {
      final nip02 = ContactList(
        pubKey: 'pubkey123',
        contacts: ['contact1', 'contact2', 'contact3'],
      );
      final myEvent = nip02.toEvent();
      expect(myEvent.pubKey, equals('pubkey123'));
      expect(myEvent.kind, equals(ContactList.kKind));
      expect(
        myEvent.tags,
        equals([
          ['p', 'contact1', '', ''],
          ['p', 'contact2', '', ''],
          ['p', 'contact3', '', ''],
        ]),
      );
      expect(myEvent.content, equals(''));
      expect(myEvent.createdAt, equals(nip02.createdAt));
    });
  });
}
