import 'dart:async';
import 'dart:collection';

/// At most [limit] publishes at once, handed out in the order they were
/// asked for.
class PublishSlots {
  final int limit;
  int _held = 0;
  final Queue<Completer<void Function()>> _waiting = Queue();

  PublishSlots(this.limit);

  /// Completes with the function that gives the slot back, once one is free.
  Future<void Function()> acquire() {
    if (_held < limit) {
      _held++;
      return Future.value(_release);
    }
    final waiter = Completer<void Function()>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _held--;
    } else {
      _waiting.removeFirst().complete(_release);
    }
  }
}
