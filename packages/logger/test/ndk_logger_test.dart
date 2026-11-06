import 'package:ndk_logger/ndk_logger.dart';
import 'package:test/test.dart';

class _Collect extends LogOutput {
  final events = <LogEvent>[];

  @override
  void output(LogEvent event) => events.add(event);
}

void main() {
  test('logs at and above its level, to every output', () {
    final output = _Collect();
    final logger = NdkLogger(level: LogLevel.warning, outputs: [output]);

    logger.i(() => 'info');
    logger.w(() => 'warning');
    logger.e(() => 'error');

    expect(output.events.map((e) => e.message), ['warning', 'error']);
  });

  test('does not build a message it will not log', () {
    final logger = NdkLogger(level: LogLevel.off, outputs: [_Collect()]);
    var built = false;

    logger.f(() {
      built = true;
      return 'fatal';
    });

    expect(built, isFalse);
  });

  test('Logger.setLogLevel changes the shared logger', () {
    final previous = Logger.log.level;
    addTearDown(() => Logger.setLogLevel(previous));

    Logger.setLogLevel(LogLevel.error);

    expect(Logger.log.level, LogLevel.error);
  });
}
