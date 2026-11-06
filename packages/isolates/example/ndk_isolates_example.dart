import 'package:ndk_isolates/ndk_isolates.dart';

int fibonacci(int n) => n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2);

Future<void> main() async {
  print(await IsolateManager.instance.runInComputeIsolate(fibonacci, 30));
  await IsolateManager.instance.dispose();
}
