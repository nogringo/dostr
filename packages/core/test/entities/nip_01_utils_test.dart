import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

void main() {
  final event = Nip01Event(
    pubKey: 'a' * 64,
    createdAt: 1,
    kind: 1,
    tags: [
      ['e', 'root', '', 'root'],
      ['e', 'parent', '', 'reply'],
      ['d', 'slug'],
      ['t', 'Nostr'],
    ],
    content: '',
  );

  test('the deprecated members still read the tags', () {
    expect(event.getEId(), 'root');
    expect(event.getDtag(), 'slug');
    expect(event.tTags, ['Nostr']);
    expect(event.replyETags, ['parent']);
  });

  test('Nip01Utils checks and computes the id', () {
    expect(Nip01Utils.isIdValid(event), isTrue);
    expect(Nip01Utils.calculateId(event), event.id);
  });
}
