import 'package:ndk_auth/ndk_auth.dart';
import '../../entities/blob_upload_progress.dart';
import '../../entities/blossom_blobs.dart';
import '../../entities/blossom_strategies.dart';
import '../../entities/ndk_file.dart';
import 'blossom.dart';

/// high level usecase to manage files on nostr
class Files {
  final Blossom _blossom;

  Files(this._blossom);

  /// the sha256 a blossom [url] names, null for any other url
  static String? _sha256Of(String url) =>
      Blossom.sha256Regex.firstMatch(url)?.group(1);

  /// upload a file to the server(s) \
  /// if [serverUrls] is null, the userServerList is fetched from nostr. \
  /// if no serverUrls (param or nostr) are found, throws an error
  /// [strategy] is the upload strategy, default is mirrorAfterSuccess \
  /// [serverMediaOptimisation] is whether the server should optimise the media [BUD-05], IMPORTANT: the server hash will be different \
  /// [auth] says which identity the upload may be attributed to, see
  /// [AuthPolicy].
  Future<List<BlobUploadResult>> upload({
    required NdkFile file,
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
  /// [serverUrls] and [pubkey] are used to download from blossom \
  /// if [serverUrls] is null, the userServerList is fetched from nostr (using the pubkey). \
  /// if both [serverUrls] and [pubkey] are null, throws an error.
  /// [auth] says which identity the download may be attributed to, see
  /// [AuthPolicy]. It is ignored for a plain url, which is fetched directly
  /// and never speaks blossom.
  Future<BlobResponse> download({
    required String url,
    List<String>? serverUrls,
    String? pubkey,
    AuthPolicy? auth,
  }) async {
    final sha256 = _sha256Of(url);
    if (sha256 == null) return _blossom.directDownload(url: Uri.parse(url));

    return _blossom.getBlob(
      sha256: sha256,
      serverUrls: serverUrls,
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
  /// [serverUrls] and [pubkey] are used to download from blossom \
  /// if [serverUrls] is null, the userServerList is fetched from nostr (using the pubkey). \
  /// if both [serverUrls] and [pubkey] are null, throws an error.
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
    final sha256 = _sha256Of(url);
    if (sha256 == null) {
      return _blossom.directDownloadToFile(
        url: Uri.parse(url),
        outputPath: outputPath,
      );
    }

    return _blossom.downloadBlobToFile(
      sha256: sha256,
      outputPath: outputPath,
      auth: auth,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkey,
    );
  }

  /// checks if a url is a blossom url. \
  /// it its not a blossom url, the url is returned. \
  /// if its a blossom url, blossom is used to check if the blob exists on the server(s) \
  /// returns alive url if the blob exists, throws an error if the blob does not exist
  /// [auth] says which identity the check may be attributed to, see
  /// [AuthPolicy]. It is ignored for a plain url, which is returned as is.
  Future<String> checkUrl({
    required String url,
    List<String>? serverUrls,
    String? pubkey,
    AuthPolicy? auth,
  }) async {
    final sha256 = _sha256Of(url);
    if (sha256 == null) return url;

    return _blossom.checkBlob(
      sha256: sha256,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkey,
      auth: auth,
    );
  }
}
