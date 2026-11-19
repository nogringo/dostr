import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import '../../domain_layer/entities/file_hash_progress.dart';
import 'file_io.dart';

UnsupportedError _noFilePaths() => UnsupportedError(
  'A browser has no file paths to read: upload with uploadBlobFromStream, '
  'from the file the app picked',
);

/// Web implementation: a browser has no file paths, so reading one fails with
/// an [UnsupportedError], and writing one hands the bytes to the browser's
/// download, the path naming the file.
class WebFileIO implements FileIO {
  @override
  Stream<Uint8List> readFileAsStream(String filePath, {int chunkSize = 8192}) =>
      Stream.error(_noFilePaths());

  @override
  Future<void> writeFile(String filePath, Uint8List data) async {
    _download(filePath, Blob([data.toJS].toJS));
  }

  /// Hands each chunk to the browser as it arrives, which keeps the blob out
  /// of the Dart heap and lets the browser spill it to disk. The download
  /// itself only starts once the stream is done.
  @override
  Future<void> writeFileStream(
    String filePath,
    Stream<Uint8List> dataStream,
  ) async {
    final parts = <Blob>[];
    await for (final chunk in dataStream) {
      parts.add(Blob([chunk.toJS].toJS));
    }
    _download(filePath, Blob(parts.toJS));
  }

  @override
  Future<int> getFileSize(String filePath) async => throw _noFilePaths();

  @override
  Future<bool> fileExists(String filePath) async => throw _noFilePaths();

  @override
  Future<Uint8List> readFile(String filePath) async => throw _noFilePaths();

  @override
  Stream<FileHashProgress> computeFileHash(String filePath) =>
      Stream.error(_noFilePaths());

  /// Download a file to the user's downloads folder using browser download
  /// This is the web equivalent of saving to a file path
  void _download(String filename, Blob blob) {
    final url = URL.createObjectURL(blob);
    final anchor = document.createElement('a') as HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = 'none';

    document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    URL.revokeObjectURL(url);
  }
}
