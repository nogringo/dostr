import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:test/test.dart';

const pubkey =
    '460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c';
const relays = ['wss://relay.example.org/', 'wss://relay.example.com/'];
const regularKinds = [1, 2, 4, 5, 6, 7, 40, 41, 42, 9999, 20000, 29999, 40000];

Nip01Event event(int kind, {String? d}) => Nip01Event(
  pubkey: pubkey,
  kind: kind,
  tags: [
    if (d != null) ['d', d],
  ],
  content: '',
);

void main() {
  group('nevent', () {
    test('holds the id, author and kind of the event', () {
      final note = event(1);

      expect(note.nevent(), Nevent(eventId: note.id, author: pubkey, kind: 1));
    });

    test('holds the relays as hints', () {
      expect(event(1).nevent(relays: relays).relays, relays);
    });
  });

  group('naddr', () {
    test('holds the d tag of an addressable event', () {
      for (final kind in [30000, 30023, 39999]) {
        expect(
          event(kind, d: 'my-article').naddr(),
          Naddr(identifier: 'my-article', pubkey: pubkey, kind: kind),
          reason: 'kind $kind',
        );
      }
    });

    test('gives a replaceable event an empty identifier', () {
      for (final kind in [0, 3, 10000, 10002, 19999]) {
        for (final d in [null, 'ignored']) {
          expect(
            event(kind, d: d).naddr(),
            Naddr(identifier: '', pubkey: pubkey, kind: kind),
            reason: 'kind $kind, d tag $d',
          );
        }
      }
    });

    test('holds the relays as hints', () {
      expect(event(10002).naddr(relays: relays)?.relays, relays);
    });

    test('accepts a d tag of 255 bytes', () {
      final identifier = 'a' * 255;

      expect(event(30023, d: identifier).naddr()?.identifier, identifier);
    });

    test('is null for an addressable event without a d tag', () {
      expect(event(30023).naddr(), isNull);
    });

    test('is null for a d tag longer than 255 bytes', () {
      expect(event(30023, d: 'é' * 128).naddr(), isNull);
    });

    test('is null for a kind neither replaceable nor addressable', () {
      for (final kind in regularKinds) {
        expect(event(kind, d: 'test').naddr(), isNull, reason: 'kind $kind');
      }
    });
  });
}
