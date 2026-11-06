import 'dart:typed_data';

class NdkFile {
  final Uint8List data;

  /// hex sha256 of [data], which spares hashing it when given. A wrong one
  /// makes the servers refuse the upload.
  final String? sha256;
  final String? mimeType;

  NdkFile({required this.data, this.mimeType, this.sha256});
}
