import 'package:dostr_core/src/connections/backoff.dart';
import 'package:test/test.dart';

void main() {
  List<int> delaysInMs(Duration initial, Duration maximum) {
    final backoff = BinaryExponentialBackoff(
      initial: initial,
      maximum: maximum,
    );
    return List.generate(7, (_) => backoff.next().inMilliseconds);
  }

  test('doubles until maximum, then stays there', () {
    expect(
      delaysInMs(const Duration(seconds: 1), const Duration(seconds: 16)),
      [1000, 2000, 4000, 8000, 16000, 16000, 16000],
    );
  });

  test('stops at a maximum the doubling does not reach exactly', () {
    expect(
      delaysInMs(const Duration(milliseconds: 500), const Duration(seconds: 5)),
      [500, 1000, 2000, 4000, 5000, 5000, 5000],
    );
  });

  test('a maximum below initial never grows', () {
    expect(
      delaysInMs(const Duration(seconds: 1), const Duration(milliseconds: 300)),
      [300, 300, 300, 300, 300, 300, 300],
    );
  });
}
