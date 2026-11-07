import 'package:ndk_follows/ndk_follows.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:test/test.dart';

void main() {
  group('ContactList', () {
    test('fromEvent', () {
      final event = Nip01Event(
        pubKey: 'pubkeyUser1',
        kind: ContactList.kKind,
        content: '',
        tags: [
          ['p', 'contact1'],
          ['p', 'contact2', 'wss://relay.com', 'petname'],
          ['t', 'nostr'],
          ['a', '34550:pubkey:community'],
          ['e', 'eventId'],
          ['invalid'],
        ],
      );
      final contactList = ContactList.fromEvent(event);
      expect(contactList.contacts, ['contact1', 'contact2']);
      expect(contactList.contactRelays, ['', 'wss://relay.com']);
      expect(contactList.petnames, ['', 'petname']);
      expect(contactList.followedTags, ['nostr']);
      expect(contactList.followedCommunities, ['34550:pubkey:community']);
      expect(contactList.followedEvents, ['eventId']);
    });

    test('toEvent', () {
      final contactList = ContactList(
        pubKey: 'pubkey123',
        contacts: ['contact1', 'contact2', 'contact3'],
      )..followedTags = ['nostr'];
      final event = contactList.toEvent();
      expect(event.pubKey, 'pubkey123');
      expect(event.kind, ContactList.kKind);
      expect(event.tags, [
        ['p', 'contact1', '', ''],
        ['p', 'contact2', '', ''],
        ['p', 'contact3', '', ''],
        ['t', 'nostr'],
      ]);
      expect(event.content, '');
      expect(event.createdAt, contactList.createdAt);
    });

    test('equality', () {
      final a = ContactList(pubKey: 'pubkey', contacts: ['contact']);
      expect(a, equals(a));
      expect(a, isNot(equals(ContactList(pubKey: 'other', contacts: []))));
    });
  });
}
