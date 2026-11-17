import 'package:dostr_core/src/shared/helpers/pausable_timer.dart';
import 'package:test/test.dart';

void main() {
  const tick = Duration(milliseconds: 60);

  test('fires once its time ran out', () async {
    var fired = 0;
    PausableTimer(() => fired++).start(tick);

    await Future<void>.delayed(tick * 2);

    expect(fired, 1);
  });

  test('does not count the time it spent paused', () async {
    var fired = false;
    final timer = PausableTimer(() => fired = true)..start(tick * 2);

    await Future<void>.delayed(tick);
    timer
      ..pause()
      ..pause();
    await Future<void>.delayed(tick * 3);
    timer.resume();
    expect(fired, isFalse);
    timer.resume();
    await Future<void>.delayed(tick * 2);

    expect(fired, isTrue);
  });

  test('started while paused, waits for the resume', () async {
    var fired = false;
    final timer = PausableTimer(() => fired = true)
      ..pause()
      ..start(tick);

    await Future<void>.delayed(tick * 2);
    expect(fired, isFalse);
    timer.resume();
    await Future<void>.delayed(tick * 2);

    expect(fired, isTrue);
  });

  test('never fires once cancelled, nor twice', () async {
    var cancelled = 0;
    PausableTimer(() => cancelled++)
      ..start(tick)
      ..cancel()
      ..pause()
      ..resume();
    var fired = 0;
    final timer = PausableTimer(() => fired++)..start(tick);
    await Future<void>.delayed(tick * 2);
    timer
      ..pause()
      ..resume();
    await Future<void>.delayed(tick * 2);

    expect(cancelled, 0);
    expect(fired, 1);
  });
}
