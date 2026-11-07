import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

void main() {
  test('NdkConfig.logLevel applies to what Ndk logs while it starts', () async {
    final testOutputs = <LogEvent>[];
    final testOutput = _TestLogOutput(testOutputs);

    Logger.log.addOutput(testOutput);
    Logger.setLogLevel(LogLevel.warning);

    // no cashu seed phrase, which Cashu warns about as it is built
    final ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [],
        logLevel: LogLevel.off,
      ),
    );
    await ndk.destroy();

    Logger.log.removeOutput(testOutput);

    // Reset to default
    Logger.setLogLevel(LogLevel.warning);

    expect(testOutputs.map((e) => e.message), isEmpty);
  });
}

/// Test log output that captures events in a list
class _TestLogOutput implements LogOutput {
  final List<LogEvent> events;

  _TestLogOutput(this.events);

  @override
  void output(LogEvent event) {
    events.add(event);
  }

  @override
  void destroy() {
    // Nothing to clean up
  }
}
