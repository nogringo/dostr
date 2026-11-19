import 'dart:async';

import 'package:http/http.dart' as http;

/// Whether one operation was aborted: by its caller's [trigger], or by
/// `abortPending` on the instance running it since it started.
class OperationAbort {
  final int Function() _aborts;
  final int _abortsAtStart;

  /// the caller's trigger, which completing, with a value or an error, aborts
  /// the operation
  final Future<void>? trigger;

  bool _triggered = false;

  /// [aborts] counts the `abortPending` calls of the instance running it
  OperationAbort(int Function() aborts, this.trigger)
    : _aborts = aborts,
      _abortsAtStart = aborts() {
    final trigger = this.trigger;
    if (trigger != null) {
      unawaited(
        trigger.then(
          (_) => _triggered = true,
          onError: (Object _) => _triggered = true,
        ),
      );
    }
  }

  bool get isAborted => _triggered || _aborts() != _abortsAtStart;

  void throwIfAborted() {
    if (isAborted) throw http.RequestAbortedException();
  }
}
