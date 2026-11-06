import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web/web.dart';

import '../../domain_layer/entities/file_hash_progress.dart';
import 'file_io.dart';

/// Web platform implementation using File System Access API
/// Works on: Chrome 86+, Edge 86+, Opera 72+ (modern browsers only)
///
/// Note: This implementation requires user interaction to pick files.
/// For web, "filePath" is interpreted as:
/// - "picker" or null: Prompt user to pick a file
/// - Valid File object reference: Use that file directly
class FileIOWeb implements FileIO {
  // Cache for file handles to avoid reprompting user
  final Map<String, File> _fileCache = {};

  @override
  Stream<Uint8List> readFileAsStream(
    String filePath, {
    int chunkSize = 8192,
  }) async* {
    final file = await _getFile(filePath);
    if (file == null) {
      throw Exception('No file selected or file not found');
    }

    int offset = 0;
    final int totalSize = file.size;

    while (offset < totalSize) {
      final int end = (offset + chunkSize < totalSize)
          ? offset + chunkSize
          : totalSize;

      // Read chunk as blob slice
      final blob = file.slice(offset, end);
      final bytes = await _blobToBytes(blob);

      yield bytes;
      offset = end;
    }
  }

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
  Future<int> getFileSize(String filePath) async {
    final file = await _getFile(filePath);
    if (file == null) {
      throw Exception('No file selected or file not found');
    }
    return file.size;
  }

  @override
  Future<bool> fileExists(String filePath) async {
    return _fileCache.containsKey(filePath);
  }

  @override
  Future<Uint8List> readFile(String filePath) async {
    final file = await _getFile(filePath);
    if (file == null) {
      throw Exception('No file selected or file not found');
    }

    return await _blobToBytes(file);
  }

  /// Get file from cache or prompt user to select
  Future<File?> _getFile(String filePath) async {
    // Check cache first
    if (_fileCache.containsKey(filePath)) {
      return _fileCache[filePath];
    }

    // Prompt user to pick a file
    final file = await _promptForFile();
    if (file != null && filePath.isNotEmpty) {
      _fileCache[filePath] = file;
    }
    return file;
  }

  /// Prompt user to select a file using File System Access API
  Future<File?> _promptForFile() async {
    try {
      // Use modern File System Access API if available
      final windowObj = window as JSObject;
      final hasFilePicker = windowObj['showOpenFilePicker'];
      if (hasFilePicker != null && !hasFilePicker.isUndefined) {
        final handles = await _showOpenFilePicker();
        if (handles.isNotEmpty) {
          return await _getFileFromHandle(handles[0]);
        }
      } else {
        // Fallback to input element
        return await _promptForFileLegacy();
      }
    } catch (e) {
      // User cancelled or error occurred
      return null;
    }
    return null;
  }

  /// Use File System Access API
  Future<List<JSObject>> _showOpenFilePicker() async {
    final options =
        {'multiple': false, 'excludeAcceptAllOption': false}.jsify()
            as JSObject;

    final windowObj = window as JSObject;
    final showOpenFilePicker = windowObj['showOpenFilePicker'] as JSFunction;
    final promise =
        showOpenFilePicker.callAsFunction(windowObj, options) as JSPromise;

    final result = await promise.toDart;
    final jsArray =
        result as JSObject; // Treat as JSObject to access properties
    final lengthValue = jsArray['length'] as JSNumber?;
    final length = lengthValue != null ? lengthValue.toDartDouble.toInt() : 0;

    return List<JSObject>.generate(
      length,
      (i) => jsArray[i.toString()] as JSObject,
    );
  }

  /// Get File object from FileSystemFileHandle
  Future<File> _getFileFromHandle(JSObject handle) async {
    final getFile = handle['getFile'] as JSFunction;
    final promise = getFile.callAsFunction(handle) as JSPromise;
    final result = await promise.toDart;
    return result as File;
  }

  /// Legacy fallback using input element
  Future<File?> _promptForFileLegacy() async {
    final input = document.createElement('input') as HTMLInputElement;
    input.type = 'file';

    final completer = Completer<File?>();
    void complete(File? file) {
      if (!completer.isCompleted) completer.complete(file);
    }

    input.addEventListener(
      'change',
      (Event event) {
        final files = input.files;
        complete(files != null && files.length > 0 ? files.item(0) : null);
      }.toJS,
    );
    input.addEventListener('cancel', ((Event event) => complete(null)).toJS);
    input.click();

    return completer.future;
  }

  /// Convert Blob to Uint8List
  Future<Uint8List> _blobToBytes(Blob blob) async {
    final reader = FileReader();
    reader.readAsArrayBuffer(blob);

    final completer = Completer<Uint8List>();
    reader.addEventListener(
      'load',
      (Event event) {
        final result = reader.result as JSArrayBuffer;
        completer.complete(result.toDart.asUint8List());
      }.toJS,
    );

    reader.addEventListener(
      'error',
      (Event event) {
        completer.completeError(Exception('Failed to read blob'));
      }.toJS,
    );

    return completer.future;
  }

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

  @override
  Stream<FileHashProgress> computeFileHash(String filePath) async* {
    final file = await _getFile(filePath);
    if (file == null) {
      throw Exception('No file selected or file not found');
    }

    final totalBytes = file.size;

    final digestSink = _DigestSink();
    final input = sha256.startChunkedConversion(digestSink);

    int processedBytes = 0;
    yield FileHashProgress(
      processedBytes: processedBytes,
      totalBytes: totalBytes,
    );

    await for (var chunk in readFileAsStream(filePath)) {
      input.add(chunk);
      processedBytes += chunk.length;
      yield FileHashProgress(
        processedBytes: processedBytes,
        totalBytes: totalBytes,
      );
    }

    input.close();

    yield FileHashProgress(
      processedBytes: totalBytes,
      totalBytes: totalBytes,
      isComplete: true,
      hash: digestSink.value?.toString(),
    );
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
