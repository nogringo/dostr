import '../entities/blossom_strategies.dart';
import '../entities/blob_upload_progress.dart';
import '../entities/blossom_authorization.dart';
import '../entities/blossom_blobs.dart';
import '../entities/blossom_hash_mismatch_exception.dart';
import '../entities/blossom_request_exception.dart';
import '../entities/file_hash_progress.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

/// The authorization the mirrors of the blob a server answered with, whose
/// hash is [sha256], go out with.
typedef BlossomMirrorAuthorization =
    Future<BlossomAuthorization> Function(String sha256);

abstract class BlossomRepository {
  /// Uploads a blob using the specified strategy
  /// Returns a stream of progress updates
  ///
  /// [dataStreamFactory] must be able to produce the body more than once: it
  /// is called once per server, and once more when a server asks the upload to
  /// authorise itself.
  ///
  /// [mirrorAuthorization], when given, authorises the mirrors of
  /// [UploadStrategy.mirrorAfterSuccess] instead of [authorization]. A
  /// [serverMediaOptimisation] upload needs it: `/mirror` wants an `upload`
  /// event naming the hash the server answered with [BUD-04], not the `media`
  /// one naming the hash that was sent.
  Stream<BlobUploadProgress> uploadBlob({
    required Stream<List<int>> Function() dataStreamFactory,
    required int contentLength,
    required BlossomAuthorization authorization,
    String? contentType,
    required List<String> serverUrls,
    UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
    bool serverMediaOptimisation = false,
    BlossomMirrorAuthorization? mirrorAuthorization,
  });

  /// Asks each server whether it would accept the upload, without sending the
  /// blob [BUD-06]. With [serverMediaOptimisation] it asks `/media` [BUD-05].
  Future<List<BlobUploadCheck>> checkUpload({
    required String sha256,
    required int contentLength,
    required List<String> serverUrls,
    required BlossomAuthorization authorization,
    String? contentType,
    bool serverMediaOptimisation = false,
  });

  /// Uploads a blob from a file path using the specified strategy
  /// Reads the file in chunks to minimize memory usage
  /// For web: prompts user to select a file via File System Access API
  /// For native: filePath is the actual file system path
  /// Returns a stream of progress updates, see [uploadBlob] for
  /// [mirrorAuthorization]
  Stream<BlobUploadProgress> uploadBlobFromFile({
    required String filePath,
    required BlossomAuthorization authorization,
    String? contentType,
    required List<String> serverUrls,
    UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
    bool serverMediaOptimisation = false,
    BlossomMirrorAuthorization? mirrorAuthorization,
  });

  /// Gets a blob by trying servers sequentially until success, or throws a
  /// [BlossomRequestException]
  /// With [BlossomAuthorization.none] the server must be public
  /// If [start] and [end] are null, the entire blob is returned, and a server
  /// whose bytes do not hash to [sha256] fails with a
  /// [BlossomHashMismatchException]
  /// [start] and [end] are used to download a range of bytes, which is not
  /// checked, @see MDN HTTP range requests
  Future<BlobResponse> getBlob({
    required String sha256,
    required List<String> serverUrls,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
    int? start,
    int? end,
  });

  /// Downloads a blob directly to a file path
  /// For web: triggers browser download dialog with the file
  /// For native: saves to the file system at the given path
  /// Fails with a [BlossomHashMismatchException], and saves nothing, when the
  /// bytes do not hash to [sha256]
  Future<void> downloadBlobToFile({
    required String sha256,
    required String outputPath,
    required List<String> serverUrls,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
  });

  /// Checks if the blob exists on the server
  /// With [BlossomAuthorization.none] the server must be public
  ///
  /// returns the url of the blob on one server that has it, or throws a
  /// [BlossomRequestException]
  Future<String> checkBlob({
    required String sha256,
    required List<String> serverUrls,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
  });

  /// Directly downloads a blob from the url, without blossom
  Future<BlobResponse> directDownload({required Uri url});

  /// Directly downloads a blob from the url to a file, without blossom
  Future<void> directDownloadToFile({
    required Uri url,
    required String outputPath,
  });

  /// fetches the blob in ranges of [chunkSize] from a server that supports range
  /// requests, otherwise streams it whole from the first server that has it.
  /// The stream ends with a [BlossomHashMismatchException] when the bytes do
  /// not hash to [sha256].
  /// @see MDN HTTP range requests
  Future<Stream<BlobResponse>> getBlobStream({
    required String sha256,
    required List<String> serverUrls,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
    int chunkSize = 1024 * 1024, // 1MB chunks
  });

  /// Whether the server supports range requests for the blob, and the blob's
  /// content length in bytes when the server gives it
  Future<({bool supported, int? contentLength})> supportsRangeRequests({
    required String sha256,
    required String serverUrl,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
  });

  /// Lists blobs from the first successful server, or throws a
  /// [BlossomRequestException]
  Future<List<BlobDescriptor>> listBlobs({
    required String pubkey,
    required List<String> serverUrls,
    DateTime? since,
    DateTime? until,
    BlossomAuthorization authorization = const BlossomAuthorization.none(),
  });

  /// Attempts to delete blob from all servers
  Future<List<BlobDeleteResult>> deleteBlob({
    required String sha256,
    required List<String> serverUrls,
    required BlossomAuthorization authorization,
  });

  /// Reports a blob to the server \
  /// [sha256] is the hash of the blob \
  /// [reportEvent] is the report event
  ///
  /// returns the http status code of the server
  Future<int> report({
    required String sha256,
    required Nip01Event reportEvent,
    required String serverUrl,
  });

  /// Mirrors a blob from one server to another using the /mirror endpoint
  /// [fileUrl] is the source URL where the blob exists
  /// [serverUrl] is the target server to mirror to
  /// [sha256] is the hash of the blob
  /// [authorization] is the signed authorization event
  Future<BlobUploadResult> mirrorToServer({
    required String fileUrl,
    required String serverUrl,
    required String sha256,
    required BlossomAuthorization authorization,
  });

  /// Computes SHA256 hash of a file by reading it in chunks
  /// Returns stream updates with progress and a final event containing [FileHashProgress.hash]
  Stream<FileHashProgress> computeFileHash(String filePath);

  /// Ends the operations in flight with a `RequestAbortedException`: the
  /// request each one waits on is aborted, and none sends another, so no
  /// other server is tried. Operations started later run as usual.
  void abortPending();
}
