import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_publish_queue_sembast/dostr_publish_queue_sembast.dart';
import 'package:sembast/sembast_io.dart';

Future<void> main() async {
  // sembast_io on dart:io targets, sembast_web in the browser.
  final db = await databaseFactoryIo.openDatabase('publish_queue.db');
  final relayManager = RelayManager(
    nostrTransportFactory: webSocketTransportFactory(),
  );

  final queue = PublishQueue.withDostr(
    relayManager,
    store: SembastPublishQueueStore(db),
  )..start();

  for (final record in await queue.watchPending().first) {
    print('${record.id} is still owed to ${record.remainingRelays}');
  }

  await queue.dispose();
  await relayManager.dispose();
  await db.close();
}
