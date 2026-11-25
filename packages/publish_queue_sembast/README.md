# dostr_publish_queue_sembast

Keeps the queue of [`dostr_publish_queue`](https://pub.dev/packages/dostr_publish_queue) in a [sembast](https://pub.dev/packages/sembast) database, so the events it holds survive a restart.

## Install

```yaml
dependencies:
  dostr_publish_queue: ^0.1.0
  dostr_publish_queue_sembast: ^0.1.0
```

## Usage

Open a sembast database and give it to the queue:

```dart
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_publish_queue_sembast/dostr_publish_queue_sembast.dart';
import 'package:sembast/sembast_io.dart';

final db = await databaseFactoryIo.openDatabase('publish_queue.db');

final queue = PublishQueue.withDostr(
  relayManager,
  store: SembastPublishQueueStore(db),
)..start();

...

await queue.dispose();
await db.close();
```

Use `sembast_io` on dart:io targets and `sembast_web` in the browser.
The full example is in [example/dostr_publish_queue_sembast_example.dart](example/dostr_publish_queue_sembast_example.dart).

## Semantics

 - The records go in the store named `storeName`, `broadcasts` by default. The other stores of the database are left untouched, so the queue can share the app's database.
 - Each write of the queue is one sembast transaction, durable once it completes.
 - A store serves one queue at a time: the queue reads it once, then keeps the records in memory. Give each queue its own `storeName`.
 - Closing the database is up to you, once `dispose` of the queue completed.

## Coming from `broadcast_queue_shim_for_ndk`

The records keep the format and the keys the shim gave them.
Pass the same database, and the same `storeName` if you changed it, and the queue loads unchanged.
