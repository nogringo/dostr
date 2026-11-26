import 'package:dostr_event_store/rules.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:test/test.dart';

final _alice = 'a' * 64;
final _bob = 'b' * 64;

Nip01Event _event({int kind = 1, List<List<String>> tags = const []}) =>
    Nip01Event(
      pubkey: _alice,
      kind: kind,
      createdAt: 1000,
      tags: tags,
      content: '',
    );

void main() {
  group('deletedAddresses', () {
    test('gives the addresses of its author as addressOf gives them', () {
      final article = _event(
        kind: 30023,
        tags: [
          ['d', 'part:one'],
        ],
      );
      final relays = _event(
        kind: 10002,
        tags: [
          ['d', 'ignored'],
        ],
      );
      final request = _event(
        kind: 5,
        tags: [
          ['a', '30023:$_alice:part:one'],
          ['a', '10002:$_alice:'],
        ],
      );

      expect(deletedAddresses(request), [
        addressOf(article),
        addressOf(relays),
      ]);
    });

    test('skips another author, a regular kind and a malformed kind', () {
      final request = _event(
        kind: 5,
        tags: [
          ['a', '30023:$_bob:post'],
          ['a', '1:$_alice:'],
          ['a', '030023:$_alice:post'],
          ['a', 'x:$_alice:post'],
          ['a', '30023'],
        ],
      );

      expect(deletedAddresses(request), isEmpty);
    });
  });

  test('addressOf is null for a regular or ephemeral kind', () {
    expect(addressOf(_event()), isNull);
    expect(addressOf(_event(kind: 20001)), isNull);
  });
}
