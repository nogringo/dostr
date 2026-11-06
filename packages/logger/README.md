# ndk_logger

The logger that NDK packages share. `Logger.log` is one `NdkLogger` for the
whole process, so the level set by `NdkConfig.logLevel` or
`Logger.setLogLevel` applies to every NDK package at once.

Pure Dart, no dependencies. A package that only needs to log, such as
[`ndk_blossom`](https://pub.dev/packages/ndk_blossom), only needs this
package, not `ndk_core`.

## Install

```yaml
dependencies:
  ndk_logger: ^0.1.0
```

## Usage

```dart
import 'package:ndk_logger/ndk_logger.dart';

Logger.setLogLevel(LogLevel.info);
Logger.log.i(() => 'connected');
```

A message is a function, so it is only built when its level is enabled. The
default level is `LogLevel.warning`, written to the console with colors.

To send the logs somewhere else, extend `LogOutput`:

```dart
class ListOutput extends LogOutput {
  final events = <LogEvent>[];

  @override
  void output(LogEvent event) => events.add(event);
}

Logger.log.addOutput(ListOutput());
```

## Coming from `ndk` or `ndk_core`

`package:ndk_core/shared/logger/*.dart` and
`package:ndk_core/config/logger_defaults.dart` are now
`package:ndk_logger/ndk_logger.dart`. `package:ndk/ndk.dart` and
`package:ndk_core/ndk_core.dart` still export it.
