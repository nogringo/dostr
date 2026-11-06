import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_nip13/ndk_nip13.dart';

Future<void> main() async {
  final event = Nip01Event(
    pubKey: '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
    kind: 1,
    tags: [],
    content: 'hello nostr',
  );

  final mined = await Nip13.mineEvent(event, 10);
  print('${mined.id} has difficulty ${Nip13.getDifficulty(mined.id)}');
  print('meets its nonce target: ${Nip13.validateEvent(mined)}');
}
