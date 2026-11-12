import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart' show StreamGroup;
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../../domain_layer/entities/blob_upload_progress.dart';
import '../../../domain_layer/entities/blossom_authorization.dart';
import '../../../domain_layer/entities/blossom_blobs.dart';
import '../../../domain_layer/entities/blossom_hash_mismatch_exception.dart';
import '../../../domain_layer/entities/blossom_request_exception.dart';
import '../../../domain_layer/entities/blossom_strategies.dart';
import '../../../domain_layer/entities/file_hash_progress.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import '../../../domain_layer/repositories/blossom.dart';
import '../../http/blossom_http.dart';
import '../../io/file_io.dart';

Uint8List _bytes(List<int> chunk) =>
    chunk is Uint8List ? chunk : Uint8List.fromList(chunk);

String _authHeader(Nip01Event event) =>
    "Nostr ${base64Encode(utf8.encode(event.toJsonString()))}";

/// [path] on [serverUrl], less the trailing slash kind 10063 lists often have
Uri _endpoint(String serverUrl, String path) {
  var base = serverUrl;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return Uri.parse('$base/$path');
}

/// the error for [serverUrl] serving bytes that hash to [actual] when asked for
/// the blob [sha256], null when they are that blob
BlossomHashMismatchException? _mismatch(
  String serverUrl,
  String sha256,
  String actual,
) => actual == sha256.toLowerCase()
    ? null
    : BlossomHashMismatchException(
        serverUrl: serverUrl,
        expected: sha256,
        actual: actual,
      );

/// [chunks] of the blob [sha256] from [serverUrl], ending with a
/// [BlossomHashMismatchException] when they hash to anything else
Stream<BlobResponse> _verified(
  Stream<BlobResponse> chunks,
  String sha256,
  String serverUrl,
) {
  late crypto.Digest digest;
  final hashing = crypto.sha256.startChunkedConversion(
    ChunkedConversionSink<crypto.Digest>.withCallback(
      (digests) => digest = digests.single,
    ),
  );
  var failed = false;

  return chunks.transform(
    StreamTransformer.fromHandlers(
      handleData: (chunk, sink) {
        hashing.add(chunk.data);
        sink.add(chunk);
      },
      handleError: (error, stackTrace, sink) {
        failed = true;
        sink.addError(error, stackTrace);
      },
      handleDone: (sink) {
        if (!failed) {
          hashing.close();
          final mismatch = _mismatch(serverUrl, sha256, digest.toString());
          if (mismatch != null) sink.addError(mismatch);
        }
        sink.close();
      },
    ),
  );
}

int? _statusCode(Object error) =>
    error is HttpRequestException ? error.statusCode : null;

/// the human readable explanation a server may give with an error [BUD-01]
String? _reason(Object error) =>
    error is HttpRequestException ? error.headers['x-reason'] : null;

BlobUploadResult _uploadFailure(String serverUrl, Object error) =>
    BlobUploadResult(
      serverUrl: serverUrl,
      success: false,
      error: error.toString(),
      statusCode: _statusCode(error),
      reason: _reason(error),
    );

BlobUploadResult _uploadSuccess(String serverUrl, http.Response response) =>
    BlobUploadResult(
      serverUrl: serverUrl,
      success: true,
      descriptor: BlobDescriptor.fromJson(jsonDecode(response.body)),
      statusCode: response.statusCode,
    );

/// The first error of a stream delegated with `yield*`. Unlike `await for`,
/// which only notices a cancelled listener at the next event, `yield*` cancels
/// the stream at once, even while it waits on a server. But it forwards errors
/// instead of raising them in the generator, so they are kept here.
class _Caught {
  Object? error;
  StackTrace? _stackTrace;

  Stream<T> from<T>(Stream<T> stream) =>
      stream.handleError((Object error, StackTrace stackTrace) {
        this.error ??= error;
        _stackTrace ??= stackTrace;
      });

  Never raise() => Error.throwWithStackTrace(error!, _stackTrace!);

  /// Adds the failed upload to [results], unless it was aborted, which ends
  /// the whole operation instead.
  void recordUploadFailure(String serverUrl, List<BlobUploadResult> results) {
    final error = this.error;
    if (error == null) return;
    if (error is http.RequestAbortedException) raise();
    results.add(_uploadFailure(serverUrl, error));
  }
}

/// Whether a server refused the request's authorization, or the lack of one.
/// BUD-01 says 401 and some servers say 403. Whether a replay could change
/// anything is for [BlossomAuthorization.onRefusal] to say.
bool _isAuthRefusal(Object error) =>
    error is HttpRequestException &&
    (error.statusCode == 401 || error.statusCode == 403);

/// What to send [serverUrl] before it refuses: the upfront event, or the one
/// an earlier refusal from that same server already signed.
Nip01Event? _initial(BlossomAuthorization authorization, String serverUrl) =>
    authorization.upfront ?? authorization.resolvedFor(serverUrl);

class BlossomRepositoryImpl implements BlossomRepository {
  final BlossomHttp _http;
  final FileIO fileIO;

  /// how many times [abortPending] ran
  int _aborts = 0;

  BlossomRepositoryImpl({required http.Client client, required this.fileIO})
    : _http = BlossomHttp(client);

  @override
  void abortPending() {
    _aborts++;
    _http.abortPending();
  }

  /// An operation reads [_aborts] before it waits on something other than a
  /// request, such as a signer, and checks it before sending again.
  void _throwIfAbortedSince(int aborts) {
    if (_aborts != aborts) throw http.RequestAbortedException();
  }

  /// Sends, and sends once more with another event if the server refused the
  /// first try and the authorization has one to offer.
  Future<T> _withAuthRetry<T>(
    BlossomAuthorization authorization,
    String serverUrl,
    Future<T> Function(Nip01Event? authEvent) send,
  ) async {
    final aborts = _aborts;
    final initial = _initial(authorization, serverUrl);
    try {
      return await send(initial);
    } catch (e) {
      if (!_isAuthRefusal(e)) rethrow;
      final signed = await authorization.onRefusal(serverUrl, refused: initial);
      if (signed == null) rethrow;
      _throwIfAbortedSince(aborts);
      return await send(signed);
    }
  }

  @override
  Stream<BlobUploadProgress> uploadBlob({
    required Stream<List<int>> Function() dataStreamFactory,
    required int contentLength,
    required BlossomAuthorization authorization,
    String? contentType,
    required List<String> serverUrls,
    UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
    bool serverMediaOptimisation = false,
    BlossomMirrorAuthorization? mirrorAuthorization,
  }) async* {
    switch (strategy) {
      case UploadStrategy.mirrorAfterSuccess:
        yield* _uploadWithMirroring(
          dataStreamFactory: dataStreamFactory,
          contentLength: contentLength,
          serverUrls: serverUrls,
          contentType: contentType,
          authorization: authorization,
          serverMediaOptimisation: serverMediaOptimisation,
          mirrorAuthorization: mirrorAuthorization,
        );
      case UploadStrategy.allSimultaneous:
        yield* _uploadToAllServers(
          dataStreamFactory: dataStreamFactory,
          contentLength: contentLength,
          serverUrls: serverUrls,
          contentType: contentType,
          authorization: authorization,
          serverMediaOptimisation: serverMediaOptimisation,
        );
      case UploadStrategy.firstSuccess:
        yield* _uploadToFirstSuccess(
          dataStreamFactory: dataStreamFactory,
          contentLength: contentLength,
          serverUrls: serverUrls,
          contentType: contentType,
          authorization: authorization,
          serverMediaOptimisation: serverMediaOptimisation,
        );
    }
  }

  @override
  Stream<BlobUploadProgress> uploadBlobFromFile({
    required String filePath,
    required BlossomAuthorization authorization,
    String? contentType,
    required List<String> serverUrls,
    UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
    bool serverMediaOptimisation = false,
    BlossomMirrorAuthorization? mirrorAuthorization,
  }) async* {
    final totalSize = await fileIO.getFileSize(filePath);

    yield* uploadBlob(
      dataStreamFactory: () =>
          fileIO.readFileAsStream(filePath, chunkSize: 1024 * 1024),
      contentLength: totalSize,
      serverUrls: serverUrls,
      contentType: contentType,
      authorization: authorization,
      strategy: strategy,
      serverMediaOptimisation: serverMediaOptimisation,
      mirrorAuthorization: mirrorAuthorization,
    );
  }

  Stream<BlobUploadProgress> _uploadWithMirroring({
    required Stream<List<int>> Function() dataStreamFactory,
    required int contentLength,
    required BlossomAuthorization authorization,
    required List<String> serverUrls,
    String? contentType,
    bool serverMediaOptimisation = false,
    BlossomMirrorAuthorization? mirrorAuthorization,
  }) async* {
    final phases = [
      UploadPhase.uploading,
      if (serverUrls.length > 1) UploadPhase.mirroring,
    ];
    final results = <BlobUploadResult>[];
    BlobUploadResult? successfulUpload;

    // Try servers until we get a successful upload
    for (final serverUrl in serverUrls) {
      final caught = _Caught();
      yield* caught.from(
        _uploadAttempt(
          serverUrl: serverUrl,
          results: results,
          onSuccess: (result) => successfulUpload = result,
          dataStreamFactory: dataStreamFactory,
          contentLength: contentLength,
          contentType: contentType,
          authorization: authorization,
          serverMediaOptimisation: serverMediaOptimisation,
          phases: phases,
        ),
      );
      // e.g. a host lookup failure
      caught.recordUploadFailure(serverUrl, results);

      if (successfulUpload != null) break;
    }

    // If we found a working server, mirror to all other servers that haven't been tried yet
    final uploaded = successfulUpload;
    if (uploaded != null) {
      final successIndex = serverUrls.indexOf(uploaded.serverUrl);
      final remainingServers = serverUrls.sublist(successIndex + 1);

      if (remainingServers.isNotEmpty) {
        final descriptor = uploaded.descriptor!;
        var mirrorsCompleted = 0;
        final mirrorsTotal = remainingServers.length;

        yield BlobUploadProgress(
          currentServer: uploaded.serverUrl,
          sentBytes: contentLength,
          totalBytes: contentLength,
          completedUploads: List.from(results),
          phase: UploadPhase.mirroring,
          phases: phases,
          progressPhase: 0,
          mirrorsTotal: mirrorsTotal,
          mirrorsCompleted: mirrorsCompleted,
        );

        // the blob is already up, so a mirror that cannot be authorised is a
        // failed mirror rather than a failed upload
        final aborts = _aborts;
        BlossomAuthorization? mirrorAuth;
        Object? mirrorAuthError;
        try {
          mirrorAuth = mirrorAuthorization == null
              ? authorization
              : await mirrorAuthorization(descriptor.sha256);
        } on http.RequestAbortedException {
          rethrow;
        } catch (error) {
          mirrorAuthError = error;
        }
        _throwIfAbortedSince(aborts);

        for (final url in remainingServers) {
          final mirrorResult = mirrorAuth == null
              ? _uploadFailure(url, mirrorAuthError!)
              : await mirrorToServer(
                  fileUrl: descriptor.url,
                  serverUrl: url,
                  sha256: descriptor.sha256,
                  authorization: mirrorAuth,
                );
          results.add(mirrorResult);
          mirrorsCompleted++;

          yield BlobUploadProgress(
            currentServer: url,
            sentBytes: contentLength,
            totalBytes: contentLength,
            completedUploads: List.from(results),
            phase: UploadPhase.mirroring,
            phases: phases,
            progressPhase: mirrorsCompleted / mirrorsTotal,
            mirrorsTotal: mirrorsTotal,
            mirrorsCompleted: mirrorsCompleted,
          );
        }
      }
    }

    // Emit final progress
    yield BlobUploadProgress(
      currentServer: '',
      sentBytes: uploaded != null ? contentLength : 0,
      totalBytes: contentLength,
      completedUploads: results,
      phase: UploadPhase.mirroring,
      phases: phases,
      progressPhase: 1,
      isComplete: true,
    );
  }

  Stream<BlobUploadProgress> _uploadToAllServers({
    required Stream<List<int>> Function() dataStreamFactory,
    required int contentLength,
    required List<String> serverUrls,
    required BlossomAuthorization authorization,
    String? contentType,
    bool serverMediaOptimisation = false,
  }) async* {
    const phases = [UploadPhase.uploading];
    final results = <BlobUploadResult>[];

    Stream<BlobUploadProgress> uploadTo(String serverUrl) async* {
      final caught = _Caught();
      yield* caught.from(
        _uploadToServer(
          serverUrl: serverUrl,
          dataStreamFactory: dataStreamFactory,
          contentLength: contentLength,
          contentType: contentType,
          authorization: authorization,
          serverMediaOptimisation: serverMediaOptimisation,
        ).map((progress) {
          if (progress.isComplete && progress.response != null) {
            results.add(_uploadSuccess(serverUrl, progress.response!));
          }
          return BlobUploadProgress(
            currentServer: serverUrl,
            sentBytes: progress.sentBytes,
            totalBytes: contentLength,
            completedUploads: List.from(results),
            phase: UploadPhase.uploading,
            phases: phases,
            progressPhase: progress.progress,
          );
        }),
      );
      if (caught.error == null) return;
      // e.g. a host lookup failure
      caught.recordUploadFailure(serverUrl, results);
      yield BlobUploadProgress(
        currentServer: serverUrl,
        sentBytes: 0,
        totalBytes: contentLength,
        completedUploads: List.from(results),
        phase: UploadPhase.uploading,
        phases: phases,
        progressPhase: 0,
      );
    }

    yield BlobUploadProgress(
      currentServer: '',
      sentBytes: 0,
      totalBytes: contentLength,
      completedUploads: [],
      phase: UploadPhase.uploading,
      phases: phases,
      progressPhase: 0,
    );

    // each server turns its failures into results, so only an abort errors here
    final caught = _Caught();
    yield* caught.from(StreamGroup.merge(serverUrls.map(uploadTo)));
    if (caught.error != null) caught.raise();

    yield BlobUploadProgress(
      currentServer: '',
      sentBytes: contentLength,
      totalBytes: contentLength,
      completedUploads: List.from(results),
      phase: UploadPhase.mirroring,
      phases: phases,
      progressPhase: 1,
      isComplete: true,
    );
  }

  Stream<BlobUploadProgress> _uploadToFirstSuccess({
    required Stream<List<int>> Function() dataStreamFactory,
    required int contentLength,
    required List<String> serverUrls,
    required BlossomAuthorization authorization,
    String? contentType,
    bool serverMediaOptimisation = false,
  }) async* {
    const phases = [UploadPhase.uploading];
    final results = <BlobUploadResult>[];

    for (final url in serverUrls) {
      BlobUploadResult? success;
      final caught = _Caught();
      yield* caught.from(
        _uploadAttempt(
          serverUrl: url,
          results: results,
          onSuccess: (result) => success = result,
          dataStreamFactory: dataStreamFactory,
          contentLength: contentLength,
          contentType: contentType,
          authorization: authorization,
          serverMediaOptimisation: serverMediaOptimisation,
          phases: phases,
        ),
      );
      // e.g. a host lookup failure
      caught.recordUploadFailure(url, results);

      if (success != null) {
        yield BlobUploadProgress(
          currentServer: url,
          sentBytes: contentLength,
          totalBytes: contentLength,
          completedUploads: results,
          phase: UploadPhase.mirroring,
          phases: phases,
          progressPhase: 1,
          isComplete: true,
        );
        return;
      }
    }

    // All servers failed
    yield BlobUploadProgress(
      currentServer: '',
      sentBytes: 0,
      totalBytes: contentLength,
      completedUploads: results,
      phase: UploadPhase.mirroring,
      phases: phases,
      progressPhase: 1,
      isComplete: true,
    );
  }

  /// One server's turn in a sequential upload. Its result goes to [results],
  /// and to [onSuccess] when the server took the blob.
  Stream<BlobUploadProgress> _uploadAttempt({
    required String serverUrl,
    required List<BlobUploadResult> results,
    required void Function(BlobUploadResult result) onSuccess,
    required Stream<List<int>> Function() dataStreamFactory,
    required int contentLength,
    required BlossomAuthorization authorization,
    required List<UploadPhase> phases,
    String? contentType,
    bool serverMediaOptimisation = false,
  }) =>
      _uploadToServer(
        serverUrl: serverUrl,
        dataStreamFactory: dataStreamFactory,
        contentLength: contentLength,
        contentType: contentType,
        authorization: authorization,
        serverMediaOptimisation: serverMediaOptimisation,
      ).map((progress) {
        final update = BlobUploadProgress(
          currentServer: serverUrl,
          sentBytes: progress.sentBytes,
          totalBytes: contentLength,
          completedUploads: results,
          phase: UploadPhase.uploading,
          phases: phases,
          progressPhase: progress.progress,
        );
        if (progress.isComplete && progress.response != null) {
          final result = _uploadSuccess(serverUrl, progress.response!);
          results.add(result);
          onSuccess(result);
        }
        return update;
      });

  /// Upload a file to a server \
  /// If [serverMediaOptimisation] is true, the server will optimise the file for media streaming using the /media endpoint [BUD-05]
  Stream<UploadProgress> _uploadToServer({
    required String serverUrl,
    required Stream<List<int>> Function() dataStreamFactory,
    required int contentLength,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
    String? contentType,
    bool serverMediaOptimisation = false,
  }) async* {
    final endpoint = _endpoint(
      serverUrl,
      serverMediaOptimisation ? 'media' : 'upload',
    );

    Map<String, String> headersFor(Nip01Event? authEvent) => {
      'Content-Type': ?contentType,
      if (authEvent != null) 'Authorization': _authHeader(authEvent),
      'Content-Length': '$contentLength',
    };

    Stream<UploadProgress> send(Nip01Event? authEvent) => _http.putStream(
      url: endpoint,
      body: dataStreamFactory(),
      headers: headersFor(authEvent),
      contentLength: contentLength,
    );

    final aborts = _aborts;
    final initial = _initial(authorization, serverUrl);
    final caught = _Caught();
    yield* caught.from(send(initial));
    final error = caught.error;
    if (error == null) return;
    if (!_isAuthRefusal(error)) caught.raise();
    final signed = await authorization.onRefusal(serverUrl, refused: initial);
    if (signed == null) caught.raise();
    _throwIfAbortedSince(aborts);
    // the body is read from scratch, so progress starts over
    yield* send(signed);
  }

  @override
  Future<List<BlobUploadCheck>> checkUpload({
    required String sha256,
    required int contentLength,
    required List<String> serverUrls,
    required BlossomAuthorization authorization,
    String? contentType,
    bool serverMediaOptimisation = false,
  }) => Future.wait(
    serverUrls.map(
      (serverUrl) => _checkUploadOnServer(
        serverUrl: serverUrl,
        sha256: sha256,
        contentLength: contentLength,
        authorization: authorization,
        contentType: contentType,
        serverMediaOptimisation: serverMediaOptimisation,
      ),
    ),
  );

  Future<BlobUploadCheck> _checkUploadOnServer({
    required String serverUrl,
    required String sha256,
    required int contentLength,
    required BlossomAuthorization authorization,
    String? contentType,
    bool serverMediaOptimisation = false,
  }) async {
    final endpoint = serverMediaOptimisation ? 'media' : 'upload';
    try {
      final response = await _withAuthRetry(
        authorization,
        serverUrl,
        (authEvent) => _http.head(
          url: _endpoint(serverUrl, endpoint),
          headers: {
            'X-SHA-256': sha256,
            'X-Content-Length': '$contentLength',
            'X-Content-Type': ?contentType,
            if (authEvent != null) 'Authorization': _authHeader(authEvent),
          },
        ),
      );
      return BlobUploadCheck(
        serverUrl: serverUrl,
        statusCode: response.statusCode,
      );
    } on http.RequestAbortedException {
      rethrow;
    } catch (e) {
      return BlobUploadCheck(
        serverUrl: serverUrl,
        statusCode: _statusCode(e),
        reason: _reason(e),
        error: e.toString(),
      );
    }
  }

  /// Mirror a file from one server to another, based on the file URL
  @override
  Future<BlobUploadResult> mirrorToServer({
    required String fileUrl,
    required String serverUrl,
    required String sha256,
    required BlossomAuthorization authorization,
  }) async {
    final body = jsonEncode({"url": fileUrl});
    try {
      final response = await _withAuthRetry(
        authorization,
        serverUrl,
        (authEvent) => _http.put(
          url: _endpoint(serverUrl, 'mirror'),
          body: body,
          headers: {
            if (authEvent != null) 'Authorization': _authHeader(authEvent),
            'Content-Type': 'application/json',
          },
        ),
      );
      return _uploadSuccess(serverUrl, response);
    } on http.RequestAbortedException {
      rethrow;
    } catch (e) {
      return _uploadFailure(serverUrl, e);
    }
  }

  @override
  Future<BlobResponse> getBlob({
    required String sha256,
    required List<String> serverUrls,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
    int? start,
    int? end,
  }) async {
    final errors = <String, Object>{};

    Map<String, String> headersFor(Nip01Event? authEvent) => {
      // Create range header in format "bytes=start-end"
      // If end is null, it means "until the end of the file"
      if (start != null) 'range': 'bytes=$start-${end ?? ''}',
      if (authEvent != null) 'Authorization': _authHeader(authEvent),
    };

    for (final url in serverUrls) {
      try {
        final response = await _withAuthRetry(
          authorization,
          url,
          (authEvent) => _http.get(
            url: _endpoint(url, sha256),
            headers: headersFor(authEvent),
          ),
        );
        final data = response.bodyBytes;
        if (start == null) {
          final mismatch = _mismatch(
            url,
            sha256,
            crypto.sha256.convert(data).toString(),
          );
          if (mismatch != null) throw mismatch;
        }
        return BlobResponse(
          data: data,
          mimeType: response.headers['content-type'],
          contentLength: int.tryParse(response.headers['content-length'] ?? ''),
          contentRange: response.headers['content-range'] ?? '',
        );
      } on http.RequestAbortedException {
        rethrow;
      } catch (e) {
        errors[url] = e;
      }
    }

    throw BlossomRequestException('get', errors);
  }

  @override
  Future<String> checkBlob({
    required String sha256,
    required List<String> serverUrls,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
  }) async {
    final errors = <String, Object>{};

    for (final url in serverUrls) {
      final blobUrl = _endpoint(url, sha256);
      try {
        await _withAuthRetry(
          authorization,
          url,
          (authEvent) => _http.head(
            url: blobUrl,
            headers: <String, String>{
              if (authEvent != null) 'Authorization': _authHeader(authEvent),
            },
          ),
        );
        return blobUrl.toString();
      } on http.RequestAbortedException {
        rethrow;
      } catch (e) {
        errors[url] = e;
      }
    }

    throw BlossomRequestException('check', errors);
  }

  @override
  Future<({bool supported, int? contentLength})> supportsRangeRequests({
    required String sha256,
    required String serverUrl,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
  }) async {
    try {
      final response = await _withAuthRetry(
        authorization,
        serverUrl,
        (authEvent) => _http.head(
          url: _endpoint(serverUrl, sha256),
          headers: <String, String>{
            if (authEvent != null) 'Authorization': _authHeader(authEvent),
          },
        ),
      );

      final acceptRanges = response.headers['accept-ranges'];
      final contentLength = int.tryParse(
        response.headers['content-length'] ?? '',
      );
      return (
        supported: acceptRanges?.toLowerCase() == 'bytes',
        contentLength: contentLength,
      );
    } on http.RequestAbortedException {
      rethrow;
    } catch (e) {
      return (supported: false, contentLength: null);
    }
  }

  @override
  Future<Stream<BlobResponse>> getBlobStream({
    required String sha256,
    required List<String> serverUrls,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
    int chunkSize = 1024 * 1024, // 1MB chunks
  }) async {
    // Find a server that supports range requests
    String? supportedServer;
    int? contentLength;

    for (final url in serverUrls) {
      try {
        final rangeResponse = await supportsRangeRequests(
          sha256: sha256,
          serverUrl: url,
          authorization: authorization,
        );
        if (rangeResponse.supported) {
          supportedServer = url;
          contentLength = rangeResponse.contentLength;
          break;
        }
      } on http.RequestAbortedException {
        rethrow;
      } catch (_) {
        continue;
      }
    }

    if (supportedServer == null || contentLength == null) {
      return _wholeBlobStream(
        sha256: sha256,
        serverUrls: serverUrls,
        authorization: authorization,
      );
    }

    return _verified(
      _chunkedBlobStream(
        sha256: sha256,
        serverUrl: supportedServer,
        authorization: authorization,
        contentLength: contentLength,
        chunkSize: chunkSize,
      ),
      sha256,
      supportedServer,
    );
  }

  /// Fetches one range at a time, as the caller reads, so a large blob is
  /// never held whole in memory.
  Stream<BlobResponse> _chunkedBlobStream({
    required String sha256,
    required String serverUrl,
    required int contentLength,
    required int chunkSize,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
  }) async* {
    int offset = 0;
    while (offset < contentLength) {
      final end = (offset + chunkSize - 1).clamp(0, contentLength - 1);
      final chunk = await getBlob(
        sha256: sha256,
        serverUrls: [serverUrl],
        authorization: authorization,
        start: offset,
        end: end,
      );
      // stop rather than ask forever: the hash check fails the short blob
      if (chunk.data.isEmpty) return;
      yield chunk;
      // a server may send less than the range, or ignore it and send the whole
      // blob
      offset += chunk.data.length;
    }
  }

  /// Streams the whole blob from the first server that has it, as the caller
  /// reads, for servers without range requests.
  Future<Stream<BlobResponse>> _wholeBlobStream({
    required String sha256,
    required List<String> serverUrls,
    required BlossomAuthorization authorization,
  }) async {
    final errors = <String, Object>{};

    for (final url in serverUrls) {
      try {
        final response = await _withAuthRetry(
          authorization,
          url,
          (authEvent) => _http.getStream(
            url: _endpoint(url, sha256),
            headers: <String, String>{
              if (authEvent != null) 'Authorization': _authHeader(authEvent),
            },
          ),
        );
        return _verified(
          response.stream.map(
            (chunk) => BlobResponse(
              data: _bytes(chunk),
              mimeType: response.headers['content-type'],
              contentLength: response.contentLength,
              contentRange: response.headers['content-range'] ?? '',
            ),
          ),
          sha256,
          url,
        );
      } on http.RequestAbortedException {
        rethrow;
      } catch (e) {
        errors[url] = e;
      }
    }

    throw BlossomRequestException('get', errors);
  }

  @override
  Future<List<BlobDescriptor>> listBlobs({
    required String pubkey,
    required List<String> serverUrls,
    DateTime? since,
    DateTime? until,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
  }) async {
    final errors = <String, Object>{};
    final queryParams = <String, String>{
      if (since != null) 'since': '${since.millisecondsSinceEpoch ~/ 1000}',
      if (until != null) 'until': '${until.millisecondsSinceEpoch ~/ 1000}',
    };

    for (final url in serverUrls) {
      try {
        final response = await _withAuthRetry(
          authorization,
          url,
          (authEvent) => _http.get(
            url: _endpoint(
              url,
              'list/$pubkey',
            ).replace(queryParameters: queryParams),
            headers: <String, String>{
              if (authEvent != null) 'Authorization': _authHeader(authEvent),
            },
          ),
        );

        final List<dynamic> json = jsonDecode(response.body);
        return json.map((j) => BlobDescriptor.fromJson(j)).toList();
      } on http.RequestAbortedException {
        rethrow;
      } catch (e) {
        errors[url] = e;
      }
    }

    throw BlossomRequestException('list', errors);
  }

  @override
  Future<List<BlobDeleteResult>> deleteBlob({
    required String sha256,
    required List<String> serverUrls,
    required BlossomAuthorization authorization,
  }) => Future.wait(
    serverUrls.map(
      (url) => _deleteFromServer(
        serverUrl: url,
        sha256: sha256,
        authorization: authorization,
      ),
    ),
  );

  Future<BlobDeleteResult> _deleteFromServer({
    required String serverUrl,
    required String sha256,
    required BlossomAuthorization authorization,
  }) async {
    try {
      await _withAuthRetry(
        authorization,
        serverUrl,
        (authEvent) => _http.delete(
          url: _endpoint(serverUrl, sha256),
          headers: {
            if (authEvent != null) 'Authorization': _authHeader(authEvent),
          },
        ),
      );
      return BlobDeleteResult(serverUrl: serverUrl, success: true);
    } on http.RequestAbortedException {
      rethrow;
    } catch (e) {
      return BlobDeleteResult(
        serverUrl: serverUrl,
        success: false,
        error: e.toString(),
      );
    }
  }

  @override
  Future<BlobResponse> directDownload({required Uri url}) async {
    final response = await _http.get(url: url);
    return BlobResponse(
      data: response.bodyBytes,
      mimeType: response.headers['content-type'],
      contentLength: int.tryParse(response.headers['content-length'] ?? ''),
      contentRange: response.headers['content-range'] ?? '',
    );
  }

  @override
  Future<void> directDownloadToFile({
    required Uri url,
    required String outputPath,
  }) async {
    final response = await _http.getStream(url: url);
    await fileIO.writeFileStream(outputPath, response.stream.map(_bytes));
  }

  @override
  Future<void> downloadBlobToFile({
    required String sha256,
    required String outputPath,
    required List<String> serverUrls,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
  }) async {
    // Use the streaming method to download and write to file
    final stream = await getBlobStream(
      sha256: sha256,
      serverUrls: serverUrls,
      authorization: authorization,
    );

    await fileIO.writeFileStream(
      outputPath,
      stream.map((response) => response.data),
    );
  }

  @override
  Future<int> report({
    required String serverUrl,
    required String sha256,
    required Nip01Event reportEvent,
  }) async {
    final response = await _http.put(
      url: _endpoint(serverUrl, 'report'),
      body: jsonEncode(reportEvent.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
    return response.statusCode;
  }

  @override
  Stream<FileHashProgress> computeFileHash(String filePath) {
    return fileIO.computeFileHash(filePath);
  }
}
