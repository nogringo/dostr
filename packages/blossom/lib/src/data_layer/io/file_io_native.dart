import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain_layer/entities/file_hash_progress.dart';
import 'file_io.dart';

/// Native platform implementation using dart:io
/// Works on: Windows, macOS, Linux, Android, iOS
class FileIONative implements FileIO {
  @override
  Stream<Uint8List> readFileAsStream(String filePath, {int chunkSize = 8192}) {
    final file = File(filePath);
    return file.openRead().map((chunk) => Uint8List.fromList(chunk));
  }

  @override
  Future<void> writeFile(String filePath, Uint8List data) async {
    final file = File(filePath);
    await file.create(recursive: true);
    await file.writeAsBytes(data);
  }

  /// Writes to a temporary file renamed once complete, so a download that
  /// fails midway neither leaves a truncated file nor destroys the one that
  /// was there.
  @override
  Future<void> writeFileStream(
    String filePath,
    Stream<Uint8List> dataStream,
  ) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final partial = File('$filePath.part');
    final sink = partial.openWrite();

    try {
      await for (final chunk in dataStream) {
        sink.add(chunk);
      }
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) => null);
      if (await partial.exists()) await partial.delete();
      rethrow;
    }

    await partial.rename(filePath);
  }

  @override
  Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    return await file.length();
  }

  @override
  Future<bool> fileExists(String filePath) async {
    final file = File(filePath);
    return await file.exists();
  }

  @override
  Future<Uint8List> readFile(String filePath) async {
    final file = File(filePath);
    return await file.readAsBytes();
  }

  @override
  Stream<FileHashProgress> computeFileHash(String filePath) async* {
    final file = File(filePath);
    if (!await file.exists()) {
      throw PathNotFoundException(
        'Cannot open file',
        OSError('No such file or directory', 2),
        filePath,
      );
    }

    final messages = ReceivePort();
    final isolate = await Isolate.spawn(
      _computeFileHashTask,
      (filePath, messages.sendPort),
      onError: messages.sendPort,
      onExit: messages.sendPort,
    );
    try {
      await for (final message in messages) {
        switch (message) {
          case FileHashProgress progress:
            yield progress;
            if (progress.isComplete) return;
          case [final Object? error, final Object? stackTrace]:
            throw RemoteError('$error', '$stackTrace');
          default:
            throw StateError('hashing $filePath stopped before the end');
        }
      }
    } finally {
      messages.close();
      isolate.kill(priority: Isolate.immediate);
    }
  }
}

Future<void> _computeFileHashTask((String, SendPort) task) async {
  final (filePath, progress) = task;
  void emit(FileHashProgress update) => progress.send(update);

  final file = File(filePath);
  final totalBytes = await file.length();

  final digestSink = _DigestSink();
  final input = sha256.startChunkedConversion(digestSink);

  int processedBytes = 0;
  emit(
    FileHashProgress(processedBytes: processedBytes, totalBytes: totalBytes),
  );

  await for (final chunk in file.openRead()) {
    input.add(chunk);
    processedBytes += chunk.length;
    emit(
      FileHashProgress(processedBytes: processedBytes, totalBytes: totalBytes),
    );
  }

  input.close();

  emit(
    FileHashProgress(
      processedBytes: totalBytes,
      totalBytes: totalBytes,
      isComplete: true,
      hash: digestSink.value?.toString(),
    ),
  );
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
