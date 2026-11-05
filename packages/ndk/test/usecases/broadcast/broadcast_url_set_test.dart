import 'package:ndk/config/broadcast_defaults.dart';
import 'package:ndk/domain_layer/usecases/broadcast/broadcast_url_set.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

const author = 'author';
const bootstrap = ['wss://bootstrap.example'];

Nip01Event eventOf(int kind, List<String> pTags) => Nip01Event(
  pubKey: author,
  kind: kind,
  tags: [
    for (final p in pTags) ['p', p],
  ],
  content: '',
);

Map<String, Object?> setOf(Nip01Event event) =>
    broadcastUrlSet(event, bootstrapRelays: bootstrap).toMap();

Map<String, Object?> outbox() => const UrlSet.fallback([
  UrlSet.outbox(author),
  UrlSet.explicit(bootstrap),
]).toMap();

Map<String, Object?> inbox(String p) => UrlSet.first(
  BroadcastDefaults.MAX_INBOX_RELAYS_TO_BROADCAST,
  UrlSet.inbox(p),
).toMap();

void main() {
  test('sends to the outbox, or the bootstrap relays without a NIP-65', () {
    expect(setOf(eventOf(Nip01Event.kTextNoteKind, [])), {
      'type': 'union',
      'sets': [outbox()],
    });
  });

  test('adds the first inbox relays of each tag, once per pubkey', () {
    expect(setOf(eventOf(Nip01Event.kTextNoteKind, ['bob', 'carol', 'bob'])), {
      'type': 'union',
      'sets': [outbox(), inbox('bob'), inbox('carol')],
    });
  });

  test('keeps a contact list out of the inboxes it tags', () {
    expect(setOf(eventOf(ContactList.kKind, ['bob'])), {
      'type': 'union',
      'sets': [outbox()],
    });
  });

  test('sends a gift wrap to the DM relays of its recipients only', () {
    expect(setOf(eventOf(GiftWrap.kGiftWrapEventkind, ['bob'])), {
      'type': 'union',
      'sets': [const UrlSet.dm('bob').toMap()],
    });
  });
}
