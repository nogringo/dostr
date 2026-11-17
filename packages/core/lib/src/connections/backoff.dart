/// Delays that start at [initial] and double on each [next], up to [maximum].
class BinaryExponentialBackoff {
  BinaryExponentialBackoff({required this.initial, required this.maximum});

  final Duration initial;
  final Duration maximum;
  late Duration _delay = initial < maximum ? initial : maximum;

  Duration next() {
    final delay = _delay;
    final doubled = delay * 2;
    _delay = doubled < maximum ? doubled : maximum;
    return delay;
  }
}
