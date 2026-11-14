import 'package:dostr_signer/dostr_signer.dart';
import '../../entities/blob_upload_progress.dart';
import '../../entities/blossom_blobs.dart';
import '../../entities/blossom_strategies.dart';
import '../../entities/blossom_file.dart';
import 'blossom.dart';

/// high level usecase to manage files on nostr
class Files {
  final Blossom _blossom;

  Files(this._blossom);

  /// the blob a blossom [url] names, and the server it names it on, which a
  /// read tries first; null for any other url
  static ({String sha256, String server})? _blobOf(String url) {
    final match = Blossom.sha256Regex.firstMatch(url);
    if (match == null) return null;
    return (sha256: match.group(1)!, server: url.substring(0, match.start));
  }

  /// upload a file to the server(s) \
  /// if [serverUrls] is null, the userServerList is fetched from nostr. \
  /// if no serverUrls (param or nostr) are found, throws an error
  /// [strategy] is the upload strategy, default is mirrorAfterSuccess \
  /// [serverMediaOptimisation] is whether the server should optimise the media [BUD-05], IMPORTANT: the server hash will be different \
  /// [auth] says which identity the upload may be attributed to, see
  /// [AuthPolicy].
  Future<List<BlobUploadResult>> upload({
    required BlossomFile file,
    List<String>? serverUrls,
    UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
    bool serverMediaOptimisation = false,
    AuthPolicy? auth,
  }) {
    return _blossom.uploadBlob(
      data: file.data,
      serverUrls: serverUrls,
      contentType: file.mimeType,
      strategy: strategy,
      serverMediaOptimisation: serverMediaOptimisation,
      auth: auth,
      precomputedSha256: file.sha256,
    );
  }

  /// Upload a file from disk path
  /// For native platforms (Windows, macOS, Linux, Android, iOS): uses actual file system paths
  /// For web: prompts user to select a file using File System Access API (modern browsers)
  ///
  /// if [serverUrls] is null, the userServerList is fetched from nostr. \
  /// if no serverUrls (param or nostr) are found, throws an error
  /// [serverMediaOptimisation] is whether the server should optimise the media [BUD-05], IMPORTANT: the server hash will be different \
  /// [auth] says which identity the upload may be attributed to, see
  /// [AuthPolicy].
  Stream<BlobUploadProgress> uploadFromFile({
    required String filePath,
    List<String>? serverUrls,
    String? contentType,
    UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
    bool serverMediaOptimisation = false,
    AuthPolicy? auth,
  }) {
    return _blossom.uploadBlobFromFile(
      filePath: filePath,
      serverUrls: serverUrls,
      contentType: contentType,
      strategy: strategy,
      serverMediaOptimisation: serverMediaOptimisation,
      auth: auth,
    );
  }

  /// deletes a file from the server(s) \
  /// if [serverUrls] is null, the userServerList is fetched from nostr. \
  /// [auth] says which identity the deletion may be attributed to, see
  /// [AuthPolicy].
  Future<List<BlobDeleteResult>> delete({
    required String sha256,
    List<String>? serverUrls,
    AuthPolicy? auth,
  }) {
    return _blossom.deleteBlob(
      sha256: sha256,
      serverUrls: serverUrls,
      auth: auth,
    );
  }

  /// download a file from the server(s) \
  /// if its a blossom url (sha256 in url), blossom is used to download \
  /// if its a public url, the file is downloaded directly \
  /// \
  /// A blossom url is read from its own server first, then from [serverUrls],
  /// then from [pubkey]'s server list (kind 10063), which is read only once
  /// none of the others had the blob. Bytes that do not hash to the url's
  /// sha256 are refused, see [Blossom.getBlob].
  /// [auth] says which identity the download may be attributed to, see
  /// [AuthPolicy]. It is ignored for a plain url, which is fetched directly
  /// and never speaks blossom.
  Future<BlobResponse> download({
    required String url,
    List<String>? serverUrls,
    String? pubkey,
    AuthPolicy? auth,
  }) async {
    final blob = _blobOf(url);
    if (blob == null) return _blossom.directDownload(url: Uri.parse(url));

    return _blossom.getBlob(
      sha256: blob.sha256,
      serverUrls: [blob.server, ...?serverUrls],
      pubkeyToFetchUserServerList: pubkey,
      auth: auth,
    );
  }

  /// Downloads a file directly to disk path (without loading whole file into memory)
  /// For native platforms (Windows, macOS, Linux, Android, iOS): uses actual file system paths
  /// For web: triggers browser download dialog to save the file
  ///
  /// if its a blossom url (sha256 in url), blossom is used to download \
  /// if its a public url, the file is downloaded directly \
  /// \
  /// Servers are tried as in [download].
  /// [auth] says which identity the download may be attributed to, see
  /// [AuthPolicy]. It is ignored for a plain url, which is fetched directly
  /// and never speaks blossom.
  Future<void> downloadToFile({
    required String url,
    required String outputPath,
    AuthPolicy? auth,
    List<String>? serverUrls,
    String? pubkey,
  }) async {
    final blob = _blobOf(url);
    if (blob == null) {
      return _blossom.directDownloadToFile(
        url: Uri.parse(url),
        outputPath: outputPath,
      );
    }

    return _blossom.downloadBlobToFile(
      sha256: blob.sha256,
      outputPath: outputPath,
      auth: auth,
      serverUrls: [blob.server, ...?serverUrls],
      pubkeyToFetchUserServerList: pubkey,
    );
  }

  /// checks if a url is a blossom url. \
  /// it its not a blossom url, the url is returned. \
  /// if its a blossom url, blossom is used to check if the blob exists on the server(s) \
  /// Servers are tried as in [download]. Returns [url] itself when its own
  /// server has the blob, else the url of another server that has it, and
  /// throws a [BlossomRequestException] when none has it.
  /// [auth] says which identity the check may be attributed to, see
  /// [AuthPolicy]. It is ignored for a plain url, which is returned as is.
  Future<String> checkUrl({
    required String url,
    List<String>? serverUrls,
    String? pubkey,
    AuthPolicy? auth,
  }) async {
    final blob = _blobOf(url);
    if (blob == null) return url;

    final alive = await _blossom.checkBlob(
      sha256: blob.sha256,
      serverUrls: [blob.server, ...?serverUrls],
      pubkeyToFetchUserServerList: pubkey,
      auth: auth,
    );
    // the url as given keeps its extension
    return alive == '${blob.server}/${blob.sha256}' ? url : alive;
  }
}
