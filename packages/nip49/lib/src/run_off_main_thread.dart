import 'dart:isolate';

Future<R> runOffMainThread<Q, R>(R Function(Q) task, Q argument) =>
    Isolate.run(() => task(argument));
