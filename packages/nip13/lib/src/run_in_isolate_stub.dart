/// The web has no isolates: [task] runs on the main thread.
Future<R> runInIsolate<Q, R>(R Function(Q) task, Q argument) async =>
    task(argument);
