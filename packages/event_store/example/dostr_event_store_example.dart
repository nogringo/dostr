import 'package:dostr_event_store/dostr_event_store.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

Future<void> main() async {
  final store = MemoryEventStore();
  final alice = 'a' * 64;

  final profile = Nip01Event(
    pubkey: alice,
    kind: 0,
    content: '{"name":"alice"}',
    createdAt: 1000,
  );
  final renamed = Nip01Event(
    pubkey: alice,
    kind: 0,
    content: '{"name":"Alice"}',
    createdAt: 2000,
  );
  print((await store.add(renamed)).name); // stored
  print((await store.add(profile)).name); // outdated

  final found = await store.query([
    Filter(authors: [alice], kinds: [0]),
  ]);
  print(found.single.content); // {"name":"Alice"}

  await store.close();
}
