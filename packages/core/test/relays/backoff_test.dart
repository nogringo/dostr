import 'package:dostr_core/src/backoff.dart';
import 'package:test/test.dart';

void main() {
  test('doubles until maximumStep delays, then stays there', () {
    final backoff = BinaryExponentialBackoff(
      initial: const Duration(seconds: 1),
      maximumStep: 5,
    );

    expect(List.generate(7, (_) => backoff.next().inSeconds), [
      1,
      2,
      4,
      8,
      16,
      16,
      16,
    ]);
  });

  test('a maximumStep of 1 or less never grows', () {
    for (final maximumStep in [0, 1]) {
      final backoff = BinaryExponentialBackoff(
        initial: const Duration(seconds: 1),
        maximumStep: maximumStep,
      );
      expect(List.generate(3, (_) => backoff.next().inSeconds), [1, 1, 1]);
    }
  });
}
