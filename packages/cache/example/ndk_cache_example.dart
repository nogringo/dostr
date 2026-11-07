import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

/// `dart run example/ndk_cache_example.dart`
Future<void> main() async {
  const pubkey =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
  final cache = MemCacheManager();

  final oldProfile = Nip01Event(
    pubKey: pubkey,
    kind: 0,
    content: '{"name":"alice"}',
    createdAt: 1700000000,
  );
  final newProfile = Nip01Event(
    pubKey: pubkey,
    kind: 0,
    content: '{"name":"alice (new)"}',
    createdAt: 1700000100,
  );
  final note = Nip01Event(
    pubKey: pubkey,
    kind: 1,
    content: 'hello',
    createdAt: 1700000200,
  );
  final deletion = Nip01Event(
    pubKey: pubkey,
    kind: Deletion.kKind,
    tags: [
      ['e', note.id],
    ],
    content: '',
    createdAt: 1700000300,
  );
  await cache.saveEvents([oldProfile, newProfile, note, deletion]);

  final profiles = await cache.loadEvents(kinds: [0], pubKeys: [pubkey]);
  print('visible profile: ${profiles.single.content}');

  final notes = await cache.loadEvents(kinds: [1], pubKeys: [pubkey]);
  print('visible notes: ${notes.length}');

  final hidden = await cache.loadHiddenEvents(pubKeys: [pubkey]);
  for (final event in hidden) {
    print('hidden kind ${event.event.kind}: ${event.reasons}');
  }
}
