import 'package:dostr_blossom_url/dostr_blossom_url.dart';

/// Thrown when the bytes a server served do not hash to the sha256 that was
/// asked for, so they are not that blob.
class BlossomHashMismatchException implements Exception {
  final BlossomServerUrl serverUrl;

  /// the sha256 that was asked for
  final String expected;

  /// the sha256 of what [serverUrl] served
  final String actual;

  BlossomHashMismatchException({
    required this.serverUrl,
    required this.expected,
    required this.actual,
  });

  @override
  String toString() =>
      'BlossomHashMismatchException: $serverUrl served $actual for $expected';
}
