import 'dart:typed_data';

class BlossomFile {
  final Uint8List data;

  /// hex sha256 of [data], which spares hashing it when given. A wrong one
  /// makes the servers refuse the upload.
  final String? sha256;
  final String? mimeType;

  BlossomFile({required this.data, this.mimeType, this.sha256});
}
