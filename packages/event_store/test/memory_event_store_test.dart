import 'package:dostr_event_store/dostr_event_store.dart';
import 'package:dostr_event_store_test_suite/dostr_event_store_test_suite.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:test/test.dart';

void main() {
  runEventStoreTestSuite(
    name: 'MemoryEventStore',
    createStore: MemoryEventStore.new,
  );

  test('MemoryEventStore matches nothing for a search', () async {
    final store = MemoryEventStore();
    await store.add(
      Nip01Event(pubkey: 'a' * 64, kind: 1, content: 'hello', createdAt: 1),
    );

    expect(await store.query([Filter(search: 'hello')]), isEmpty);
  });
}
