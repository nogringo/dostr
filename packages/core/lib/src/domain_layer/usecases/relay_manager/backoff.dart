/// Delays that start at [initial] and double on each [next], until they were
/// doubled `maximumStep - 1` times.
class BinaryExponentialBackoff {
  BinaryExponentialBackoff({required this.initial, required this.maximumStep});

  final Duration initial;
  final int maximumStep;
  int _doublings = 0;

  Duration next() {
    final delay = initial * (1 << _doublings);
    if (_doublings + 1 < maximumStep) _doublings++;
    return delay;
  }
}
