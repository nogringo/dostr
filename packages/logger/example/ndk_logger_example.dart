import 'package:ndk_logger/ndk_logger.dart';

void main() {
  Logger.setLogLevel(LogLevel.info);
  Logger.log.i(() => 'shown');
  Logger.log.d(() => 'hidden below info');
}
