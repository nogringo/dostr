/// The shared isolate pool of NDK. On the web, tasks run on the main thread.
library;

export 'src/isolate_manager_stub.dart'
    if (dart.library.io) 'src/isolate_manager_io.dart'
    show IsolateManager, StreamComputeTask;
