import 'dart:isolate';

Future<R> runInIsolate<Q, R>(R Function(Q) task, Q argument) =>
    Isolate.run(() => task(argument));
