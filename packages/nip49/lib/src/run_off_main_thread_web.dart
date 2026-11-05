/// Web has no isolates: the task blocks the main thread.
Future<R> runOffMainThread<Q, R>(R Function(Q) task, Q argument) async =>
    task(argument);
