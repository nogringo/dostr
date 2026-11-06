import 'package:ndk_http/ndk_http.dart';

/// Thrown when no server served a read: each one failed or refused it.
class BlossomRequestException implements Exception {
  /// what was asked, such as "get", "check" or "list"
  final String operation;

  /// why each server failed, by server url, in the order they were tried. An
  /// [HttpRequestException] carries the status the server answered with.
  final Map<String, Object> errors;

  BlossomRequestException(this.operation, this.errors);

  /// whether every server answered that it has no such blob
  bool get notFound =>
      errors.isNotEmpty &&
      errors.values.every(
        (error) => error is HttpRequestException && error.statusCode == 404,
      );

  @override
  String toString() {
    if (errors.isEmpty) {
      return 'BlossomRequestException: no server to $operation from';
    }
    final reasons = errors.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('; ');
    return 'BlossomRequestException: $operation failed on every server. '
        '$reasons';
  }
}
