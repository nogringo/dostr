import 'package:ndk_nip01/ndk_nip01.dart';

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
  print(Nip01Utils.isIdValid(event));
}
