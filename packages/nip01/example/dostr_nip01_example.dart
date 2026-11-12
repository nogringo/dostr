import 'package:dostr_nip01/dostr_nip01.dart';

void main() {
  final event = Nip01Event(
    pubKey: 'a' * 64,
    kind: Nip01Event.kTextNoteKind,
    tags: [
      ['t', 'nostr'],
    ],
    content: 'hello',
  );

  print(event.id);
  print(event.hasValidId);
  print(event.toJsonString());
}
