import 'dart:async';

/// A one-shot timer whose countdown can be paused. Pauses nest: it runs again
/// once every pause has resumed, with the time it had left.
class PausableTimer {
  PausableTimer(this._onFire);

  final void Function() _onFire;
  final Stopwatch _elapsed = Stopwatch();
  Duration? _duration;
  Timer? _timer;
  int _pauses = 0;
  bool _over = false;

  /// Counts [duration] down, from now or from the end of the current pause.
  /// Only the first call counts, and none after [cancel].
  void start(Duration duration) {
    if (_duration != null || _over) return;
    _duration = duration;
    if (_pauses == 0) _run();
  }

  void pause() {
    if (_pauses++ > 0) return;
    _timer?.cancel();
    _timer = null;
    _elapsed.stop();
  }

  void resume() {
    if (_pauses == 0) return;
    _pauses--;
    if (_pauses == 0 && _duration != null && !_over) _run();
  }

  /// Stops it for good: it never fires.
  void cancel() {
    _over = true;
    _timer?.cancel();
    _timer = null;
  }

  void _run() {
    final left = _duration! - _elapsed.elapsed;
    _elapsed.start();
    _timer = Timer(left.isNegative ? Duration.zero : left, () {
      _over = true;
      _onFire();
    });
  }
}
