# ndk_isolates

The isolate pool that NDK shares between its packages: relay messages are
decoded in it, and signatures, proof of work and file hashes are computed in
it, off the main isolate. On the web, where Dart has no isolates, the same
calls run on the main thread.

Pure Dart, no dependencies. A package that needs the pool, such as
[`ndk_bip340`](https://pub.dev/packages/ndk_bip340), only needs this package,
not `ndk_core`.

## Install

```yaml
dependencies:
  ndk_isolates: ^0.1.0
```

## Usage

```dart
import 'package:ndk_isolates/ndk_isolates.dart';

int fibonacci(int n) => n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2);

final result = await IsolateManager.instance.runInComputeIsolate(fibonacci, 30);
```

`IsolateManager.instance` starts two pools the first time it is read, one for
JSON encoding and decoding (`runInEncodingIsolate`) and one for computing
(`runInComputeIsolate`), each with a quarter of the processors, between 1
and 32 isolates. `runInComputeIsolateStream` runs a task that reports its
progress as it goes:

```dart
final progress = IsolateManager.instance.runInComputeIsolateStream<int, int>(
  (count, emit) {
    for (var i = 1; i <= count; i++) {
      emit(i);
    }
  },
  3,
);
```

A task is sent to another isolate, so it must be a top-level or static
function, or a closure that captures only what can be sent between isolates.
`dispose` stops the isolates; the next `IsolateManager.instance` starts new
ones.

## Coming from `ndk` or `ndk_core`

`package:ndk/shared/isolates/isolate_manager.dart` and
`package:ndk_core/shared/isolates/isolate_manager.dart` are now
`package:ndk_isolates/ndk_isolates.dart`.
