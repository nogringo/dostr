import 'package:ndk_isolates/ndk_isolates.dart';
import 'package:test/test.dart';

int _square(int x) => x * x;

void main() {
  tearDownAll(() => IsolateManager.instance.dispose());

  test('runInComputeIsolate returns the result of the task', () async {
    expect(await IsolateManager.instance.runInComputeIsolate(_square, 7), 49);
  });

  test('runInEncodingIsolate returns the result of the task', () async {
    expect(await IsolateManager.instance.runInEncodingIsolate(_square, 3), 9);
  });

  test('runInComputeIsolateStream emits each progress, then ends', () async {
    final progress = IsolateManager.instance
        .runInComputeIsolateStream<int, int>((count, emit) {
          for (var i = 1; i <= count; i++) {
            emit(i);
          }
        }, 3);

    expect(await progress.toList(), [1, 2, 3]);
  });
}
