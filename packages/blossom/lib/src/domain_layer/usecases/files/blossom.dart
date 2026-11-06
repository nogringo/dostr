import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:ndk_http/ndk_http.dart';

import '../../../data_layer/io/file_io_platform.dart';
import '../../../data_layer/repositories/blossom/blossom_impl.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk_auth/ndk_auth.dart';
import '../../entities/blob_upload_progress.dart';
import '../../entities/blossom_authorization.dart';
import '../../entities/blossom_blobs.dart';
import '../../entities/blossom_hash_mismatch_exception.dart';
import '../../entities/blossom_request_exception.dart';
import '../../entities/blossom_strategies.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import '../../repositories/blossom.dart';
import 'package:ndk_signer/ndk_signer.dart';
import 'blossom_exceptions.dart';

/// The servers in [pubkey]'s Blossom server list (kind 10063, BUD-03), or
/// null when they have none.
typedef BlossomServerListResolver =
    Future<List<String>?> Function(String pubkey);

/// Builds the kind 24242 event an operation authorises itself with as
/// [pubkey].
typedef _AuthEventBuilder = Nip01Event Function(String pubkey);

/// [servers] less those an [AuthHandler] keeps an upfront authorization from
typedef _ServerFilter = Future<List<String>> Function(List<String> servers);

/// [servers] less those [seen] already names, a trailing slash aside. The ones
/// it keeps join [seen].
List<String> _distinctServers(Iterable<String> servers, Set<String> seen) => [
  for (final server in servers)
    if (seen.add(server.replaceFirst(RegExp(r'/+$'), ''))) server,
];

/// What one blossom operation does about its authorization, and the servers
/// it may talk to.
class _BlossomAuthPlan {
  final BlossomAuthorization authorization;

  /// the resolved servers, less those an [AuthHandler] kept an upfront
  /// authorization from
  final List<String> servers;

  /// the servers to try once none of [servers] served the operation, resolved
  /// only then and filtered the same way, null when there are none
  final Future<List<String>> Function()? nextServers;

  /// the same identity authorising another event, for the same [servers],
  /// without asking the [AuthHandler] again
  final Future<BlossomAuthorization> Function(_AuthEventBuilder buildEvent)
  authorize;

  const _BlossomAuthPlan(
    this.authorization,
    this.servers,
    this.authorize, {
    this.nextServers,
  });
}

/// direct access usecase to blossom \
/// use files usecase for a more convenient way to manage files
class Blossom {
  /// kind of the authorization events [BUD-11]
  static const kBlossom = 24242;

  /// kind for reports NIP56
  static const int kReport = 1984;

  /// kind for blossom user server list
  static const kBlossomUserServerList = 10063;

  /// Matches the sha256 in a blob url, which may end with a file extension
  /// [BUD-01], a query or a fragment
  static final sha256Regex = RegExp(r'/([a-fA-F0-9]{64})(?=[./?#]|$)');

  /// how long a signed kind 24242 event stays valid, unless the constructor
  /// says otherwise
  static const defaultAuthExpiration = Duration(minutes: 5);

  final BlossomServerListResolver _getUserServerList;
  final BlossomRepository _blossomImpl;
  final AuthAccounts _accounts;
  final LocalEventSignerFactory _eventSignerFactory;
  final AuthHandler? _authHandler;
  final Duration _authExpiration;

  /// [accounts] gives the logged-in account, [eventSignerFactory] makes the
  /// throwaway keys, and [getUserServerList] reads a user's kind 10063 list.
  /// Without [blossomRepository], it talks to the servers over HTTP.
  ///
  /// [authExpiration] is how long a signed kind 24242 event stays valid. An
  /// operation that outlives it signs a new one when a server refuses the
  /// expired one.
  Blossom({
    required AuthAccounts accounts,
    required LocalEventSignerFactory eventSignerFactory,
    required BlossomServerListResolver getUserServerList,
    AuthHandler? authHandler,
    BlossomRepository? blossomRepository,
    Duration authExpiration = defaultAuthExpiration,
  }) : _accounts = accounts,
       _authExpiration = authExpiration,
       _getUserServerList = getUserServerList,
       _blossomImpl =
           blossomRepository ??
           BlossomRepositoryImpl(
             client: NdkHttp(http.Client()),
             fileIO: createFileIO(),
           ),
       _eventSignerFactory = eventSignerFactory,
       _authHandler = authHandler;

  /// how many times [abortPending] ran
  int _aborts = 0;

  /// Ends the operations in flight with a `RequestAbortedException` (from
  /// `package:http`), including those still waiting on relays, on the
  /// [AuthHandler] or on a signer: none sends a request afterwards. This
  /// instance stays usable.
  void abortPending() {
    _aborts++;
    _blossomImpl.abortPending();
  }

  void _throwIfAbortedSince(int aborts) {
    if (_aborts != aborts) throw http.RequestAbortedException();
  }

  /// The kind 24242 event an operation authorises itself with. Built when it
  /// is needed rather than when the call is made, so an event signed after a
  /// refusal is not already ageing.
  Nip01Event _blossomAuthEvent({
    required String content,
    required String pubkey,
    required String type,
    String? blobSha256,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    return Nip01Event(
      content: content,
      pubKey: pubkey,
      kind: kBlossom,
      createdAt: now,
      tags: [
        ["t", type],
        if (blobSha256 != null) ["x", blobSha256],
        ["expiration", "${now + _authExpiration.inSeconds}"],
      ],
    );
  }

  /// The logged-in account when an [AuthHandler] may agree to revealing it.
  /// Without one, an operation that names nobody reveals nobody.
  Account? _defaultAccount() {
    final account = _accounts.getLoggedAccount();
    return _authHandler != null && account != null && account.signer.canSign()
        ? account
        : null;
  }

  Account _throwawayAccount() {
    final signer = _throwawaySigner();
    return Account(
      type: AccountType.privateKey,
      pubkey: signer.getPublicKey(),
      signer: signer,
    );
  }

  /// Whether [serverUrl] may see [pubkey]. A failing [AuthHandler] says no.
  Future<bool> _consent(String serverUrl, String pubkey) async {
    final handler = _authHandler;
    if (handler == null) return true;
    try {
      return await handler(serverUrl, pubkey);
    } catch (error, stackTrace) {
      Logger.log.w(
        () => "AuthHandler failed for $pubkey on $serverUrl",
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Turns the caller's intent into what the repository does about the
  /// `Authorization` header, and into the servers it may send it to.
  ///
  /// Without [auth], an operation that [authorisesByDefault] requires
  /// [_defaultAccount], or a throwaway key when there is none, and any other
  /// stays anonymous. [buildEvent] makes the kind 24242 event, because only the
  /// operation knows its `t` and `x` tags.
  ///
  /// [resolveNextServers] gives the servers to try once none of
  /// [resolveServers] served the operation. It is read then, or right away
  /// when the [AuthHandler] keeps every first server from the identity.
  ///
  /// Throws [BlossomAuthUnavailableException], before anything is sent, when
  /// [auth] requires an identity that cannot sign or that no server may see.
  Future<_BlossomAuthPlan> _planAuth({
    required AuthPolicy? auth,
    required bool authorisesByDefault,
    required String operation,
    required _AuthEventBuilder buildEvent,
    required Future<List<String>> Function() resolveServers,
    Future<List<String>> Function()? resolveNextServers,
  }) async {
    final aborts = _aborts;
    final fallback = authorisesByDefault ? _defaultAccount() : null;
    final throwaway = auth == null && authorisesByDefault && fallback == null;
    final policy =
        auth ??
        (authorisesByDefault
            ? AuthPolicy.require(fallback ?? _throwawayAccount())
            : const AuthPolicy.never());

    var resolveNext = resolveNextServers;
    _ServerFilter admit = (servers) async => servers;
    final List<String> servers;
    final Future<BlossomAuthorization> Function(_AuthEventBuilder) authorize;
    switch (policy) {
      case AuthPolicyNever():
        servers = await resolveServers();
        authorize = (_) async => const BlossomAuthorization.none();

      case AuthPolicyRequire(:final account):
        if (!account.signer.canSign()) {
          throw BlossomAuthUnavailableException(account.pubkey, operation);
        }
        if (!throwaway) {
          admit = (servers) => _serversAllowing(servers, account.pubkey);
        }
        var admitted = await admit(await resolveServers());
        final next = resolveNext;
        if (admitted.isEmpty && next != null) {
          admitted = await admit(await next());
          resolveNext = null;
        }
        if (admitted.isEmpty) {
          throw BlossomAuthUnavailableException(account.pubkey, operation);
        }
        servers = admitted;
        Future<Nip01Event> sign(_AuthEventBuilder build) =>
            account.signer.sign(build(account.pubkey));
        authorize = (build) async => BlossomAuthorization.upfront(
          await sign(build),
          renew: () => sign(build),
        );

      case AuthPolicyAllow(:final account):
        servers = await resolveServers();
        // allow never promised a signature, so an account that cannot give one
        // behaves as never() rather than failing the operation
        authorize = (build) async => account.signer.canSign()
            ? BlossomAuthorization.onRefusal(
                () => account.signer.sign(build(account.pubkey)),
                consent: _authHandler == null
                    ? null
                    : (serverUrl) => _consent(serverUrl, account.pubkey),
              )
            : const BlossomAuthorization.none();
    }
    final authorization = await authorize(buildEvent);
    _throwIfAbortedSince(aborts);
    final next = resolveNext;
    return _BlossomAuthPlan(
      authorization,
      servers,
      authorize,
      nextServers: next == null ? null : () async => admit(await next()),
    );
  }

  Future<List<String>> _serversAllowing(
    List<String> servers,
    String pubkey,
  ) async {
    if (_authHandler == null) return servers;
    final answers = await Future.wait(
      servers.map((serverUrl) => _consent(serverUrl, pubkey)),
    );
    return [
      for (var i = 0; i < servers.length; i++)
        if (answers[i]) servers[i],
    ];
  }

  /// The four read operations authorise the same way: a `get` event naming the
  /// blob, and anonymous unless the caller asked otherwise.
  ///
  /// They start with [serverUrls], else with [pubkeyToFetchUserServerList]'s
  /// list. Given both, that list is read only once none of [serverUrls] served
  /// the blob. Unlike a write, a read is about somebody else's blob as often
  /// as not, so it never guesses whose list to read.
  Future<_BlossomAuthPlan> _readAuthPlan({
    required AuthPolicy? auth,
    required String sha256,
    required List<String>? serverUrls,
    required String? pubkeyToFetchUserServerList,
  }) {
    final owner = pubkeyToFetchUserServerList;
    final tried = <String>{};
    return _planAuth(
      auth: auth,
      authorisesByDefault: false,
      operation: "get",
      buildEvent: (pubkey) => _blossomAuthEvent(
        content: "get",
        pubkey: pubkey,
        type: "get",
        blobSha256: sha256,
      ),
      resolveServers: () async {
        if (serverUrls != null) return _distinctServers(serverUrls, tried);
        if (owner == null) throw const BlossomNoServerListException();
        return _distinctServers(await _userServerList(owner), tried);
      },
      resolveNextServers: serverUrls == null || owner == null
          ? null
          : () async =>
                _distinctServers(await _getUserServerList(owner) ?? [], tried),
    );
  }

  /// Runs [read] on the servers [plan] starts with, then on its next ones if
  /// none of the first served the blob.
  Future<T> _read<T>(
    _BlossomAuthPlan plan,
    Future<T> Function(BlossomAuthorization authorization, List<String> servers)
    read,
  ) async {
    final aborts = _aborts;
    try {
      return await read(plan.authorization, plan.servers);
    } on BlossomRequestException catch (first) {
      final nextServers = plan.nextServers;
      if (nextServers == null) rethrow;
      final servers = await nextServers();
      _throwIfAbortedSince(aborts);
      if (servers.isEmpty) rethrow;
      try {
        return await read(plan.authorization, servers);
      } on BlossomRequestException catch (next) {
        throw BlossomRequestException(first.operation, {
          ...first.errors,
          ...next.errors,
        });
      }
    }
  }

  /// An event authorising a [type] write of the blob [sha256], such as an
  /// `upload` or a `media` one
  _AuthEventBuilder _writeEvent(String type, String sha256) =>
      (pubkey) => _blossomAuthEvent(
        content: type,
        pubkey: pubkey,
        type: type,
        blobSha256: sha256,
      );

  /// Uploads, and the checks before them, authorise the same way: an `upload`
  /// event naming the blob, or a `media` one for [BUD-05].
  Future<_BlossomAuthPlan> _uploadAuthPlan({
    required AuthPolicy? auth,
    required String sha256,
    required bool media,
    required List<String>? serverUrls,
    required String? pubkeyToFetchUserServerList,
  }) {
    final authType = media ? "media" : "upload";
    return _planAuth(
      auth: auth,
      authorisesByDefault: true,
      operation: authType,
      buildEvent: _writeEvent(authType, sha256),
      resolveServers: () => _resolveWriteServers(
        serverUrls: serverUrls,
        explicitPubkey: pubkeyToFetchUserServerList,
        listOwner: auth?.account?.pubkey,
      ),
    );
  }

  /// What the mirrors of a [media] upload go out with: `/mirror` wants an
  /// `upload` event naming the hash the server answered with [BUD-04], which
  /// the `media` event the upload signed is not.
  BlossomMirrorAuthorization? _mirrorAuthorization(
    _BlossomAuthPlan plan, {
    required bool media,
  }) =>
      media ? (sha256) => plan.authorize(_writeEvent("upload", sha256)) : null;

  /// The servers a write talks to: an explicit list, else an explicit pubkey's
  /// kind 10063 list, else the identity the policy names, else the logged-in
  /// account's.
  ///
  /// That last fallback applies even under [AuthPolicy.never]. Reading a
  /// public kind 10063 from relays tells the blossom servers nothing, and
  /// never() is a statement about the `Authorization` header, not about which
  /// nostr list may be read.
  Future<List<String>> _resolveWriteServers({
    required List<String>? serverUrls,
    required String? explicitPubkey,
    required String? listOwner,
  }) async {
    if (serverUrls != null) return serverUrls;

    final owner =
        explicitPubkey ?? listOwner ?? _accounts.getLoggedAccount()?.pubkey;
    if (owner == null) throw const BlossomNoServerListException();
    return _userServerList(owner);
  }

  /// [pubkey]'s servers, or a [BlossomNoServerListException] when it has none
  Future<List<String>> _userServerList(String pubkey) async {
    final servers = await _getUserServerList(pubkey);
    if (servers == null || servers.isEmpty) {
      throw BlossomNoServerListException(pubkey);
    }
    return servers;
  }

  /// A fresh key, for something that has to be signed but names nobody.
  EventSigner _throwawaySigner() => _eventSignerFactory.createWithNewKeyPair();

  /// Asks each server whether it would accept this upload, before any byte of
  /// the blob is sent [BUD-06]. Servers and authorization resolve as in
  /// [uploadBlob], so the answer is about the identity the upload will use.
  ///
  /// Only a hint: BUD-06 is optional, so a server without it answers something
  /// like 404, and an accepted check does not promise the upload.
  Future<List<BlobUploadCheck>> checkUpload({
    required String sha256,
    required int contentLength,
    String? contentType,
    List<String>? serverUrls,
    bool serverMediaOptimisation = false,
    AuthPolicy? auth,
    String? pubkeyToFetchUserServerList,
  }) async {
    final plan = await _uploadAuthPlan(
      auth: auth,
      sha256: sha256,
      media: serverMediaOptimisation,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
    );

    return _blossomImpl.checkUpload(
      sha256: sha256,
      contentLength: contentLength,
      serverUrls: plan.servers,
      authorization: plan.authorization,
      contentType: contentType,
      serverMediaOptimisation: serverMediaOptimisation,
    );
  }

  /// upload a blob to the server
  /// if [serverUrls] is null, the userServerList is fetched from nostr. \
  /// if it has none, or an empty one, throws a [BlossomNoServerListException] \
  /// [strategy] is the upload strategy, default is mirrorAfterSuccess \
  /// [serverMediaOptimisation] is whether the server should optimise the media [BUD-05], IMPORTANT: the server hash will be different \
  /// [precomputedSha256] optional hex sha256 of [data]; if provided, skips local hashing. \
  /// Caller is responsible for correctness: a mismatched hash will cause the server to reject the upload.
  /// [auth] says which identity the upload may be attributed to, see
  /// [AuthPolicy]. Without it the upload authorises as the logged-in account
  /// on the servers an [AuthHandler] agrees to, or as a throwaway key when
  /// there is no handler or no account.
  ///
  /// Throws [BlossomAuthUnavailableException], before anything is sent, if
  /// [auth] requires an identity that cannot sign or no server may see.
  Future<List<BlobUploadResult>> uploadBlob({
    required Uint8List data,
    List<String>? serverUrls,
    String? contentType,
    UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
    bool serverMediaOptimisation = false,
    AuthPolicy? auth,
    String? pubkeyToFetchUserServerList,
    String? precomputedSha256,
  }) async {
    /// sha256 of the data
    final dataSha256 = precomputedSha256 ?? sha256.convert(data).toString();

    final plan = await _uploadAuthPlan(
      auth: auth,
      sha256: dataSha256,
      media: serverMediaOptimisation,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
    );

    final stream = _blossomImpl.uploadBlob(
      dataStreamFactory: () => Stream.value(data),
      contentLength: data.length,
      serverUrls: plan.servers,
      authorization: plan.authorization,
      contentType: contentType,
      strategy: strategy,
      serverMediaOptimisation: serverMediaOptimisation,
      mirrorAuthorization: _mirrorAuthorization(
        plan,
        media: serverMediaOptimisation,
      ),
    );

    final done = await stream.last;

    return done.completedUploads;
  }

  /// Upload a blob from a file path
  /// For native platforms (Windows, macOS, Linux, Android, iOS): uses actual file system paths
  /// For web: prompts user to select a file using File System Access API (modern browsers)
  ///
  /// if [serverUrls] is null, the userServerList is fetched from nostr. \
  /// if it has none, or an empty one, throws a [BlossomNoServerListException] \
  /// [strategy] is the upload strategy, default is mirrorAfterSuccess \
  /// [serverMediaOptimisation] is whether the server should optimise the media [BUD-05], IMPORTANT: the server hash will be different \
  /// [precomputedSha256] optional hex sha256 of the file; if provided, skips the [UploadPhase.hashing] phase entirely. \
  /// Caller is responsible for correctness: a mismatched hash will cause the server to reject the upload.
  /// [auth] says which identity the upload may be attributed to, see
  /// [AuthPolicy]. Without it the upload authorises as the logged-in account
  /// on the servers an [AuthHandler] agrees to, or as a throwaway key when
  /// there is no handler or no account.
  Stream<BlobUploadProgress> uploadBlobFromFile({
    required String filePath,
    List<String>? serverUrls,
    String? contentType,
    UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
    bool serverMediaOptimisation = false,
    AuthPolicy? auth,
    String? pubkeyToFetchUserServerList,
    String? precomputedSha256,
  }) async* {
    final aborts = _aborts;
    String? fileHash = precomputedSha256;
    final hashes = fileHash == null;

    if (hashes) {
      // the servers are not resolved yet, so assume the mirrors take place:
      // progress may then skip ahead, but never back
      final phases = [
        UploadPhase.hashing,
        UploadPhase.uploading,
        if (strategy == UploadStrategy.mirrorAfterSuccess &&
            (serverUrls == null || serverUrls.length > 1))
          UploadPhase.mirroring,
      ];
      // Compute file hash without loading entire file into memory
      await for (final hashProgress in _blossomImpl.computeFileHash(filePath)) {
        yield BlobUploadProgress(
          currentServer: '',
          sentBytes: hashProgress.processedBytes,
          totalBytes: hashProgress.totalBytes,
          completedUploads: const [],
          phase: UploadPhase.hashing,
          phases: phases,
          progressPhase: hashProgress.progress,
        );

        if (hashProgress.isComplete && hashProgress.hash != null) {
          fileHash = hashProgress.hash;
        }
      }

      if (fileHash == null) {
        throw Exception('Failed to compute file hash');
      }
    }
    _throwIfAbortedSince(aborts);

    final plan = await _uploadAuthPlan(
      auth: auth,
      sha256: fileHash,
      media: serverMediaOptimisation,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
    );

    final upload = _blossomImpl.uploadBlobFromFile(
      filePath: filePath,
      serverUrls: plan.servers,
      authorization: plan.authorization,
      contentType: contentType,
      strategy: strategy,
      serverMediaOptimisation: serverMediaOptimisation,
      mirrorAuthorization: _mirrorAuthorization(
        plan,
        media: serverMediaOptimisation,
      ),
    );
    yield* hashes
        ? upload.map(
            (progress) =>
                progress.withPhases([UploadPhase.hashing, ...progress.phases]),
          )
        : upload;
  }

  /// Mirror a blob from a blossom URL to specified servers using the blossom /mirror endpoint
  ///
  /// [blossomUrl] is the source URL of the blob to mirror (e.g., https://cdn.example.com/[sha256].jpg)
  ///   The URL must contain a 64-character SHA256 hash
  /// [targetServerUrls] is the list of servers to mirror the blob to
  /// [auth] says which identity the mirror may be attributed to, see
  /// [AuthPolicy]. Without it the mirror authorises as the logged-in account
  /// on the servers an [AuthHandler] agrees to, or as a throwaway key when
  /// there is no handler or no account.
  ///
  /// Throws an [Exception] if no SHA256 hash is detected in the URL
  Future<List<BlobUploadResult>> mirrorToServers({
    required Uri blossomUrl,
    required List<String> targetServerUrls,
    AuthPolicy? auth,
  }) async {
    // Extract sha256 from the URL
    final sha256Match = sha256Regex.firstMatch(blossomUrl.toString());
    if (sha256Match == null) {
      throw Exception(
        "No SHA256 hash detected in URL: ${blossomUrl.toString()}",
      );
    }

    final sha256 = sha256Match.group(1)!;

    final plan = await _planAuth(
      auth: auth,
      authorisesByDefault: true,
      operation: "upload",
      buildEvent: _writeEvent("upload", sha256),
      resolveServers: () async => targetServerUrls,
    );

    // Mirror to all target servers
    final results = await Future.wait(
      plan.servers.map(
        (serverUrl) => _blossomImpl.mirrorToServer(
          fileUrl: blossomUrl.toString(),
          serverUrl: serverUrl,
          sha256: sha256,
          authorization: plan.authorization,
        ),
      ),
    );

    return results;
  }

  /// Gets a blob by trying servers sequentially until success (fallback), or
  /// throws a [BlossomRequestException] when none served it. A server whose
  /// bytes do not hash to [sha256] fails with a [BlossomHashMismatchException].
  ///
  /// [serverUrls] are tried first. [pubkeyToFetchUserServerList]'s server
  /// list (kind 10063) is read when [serverUrls] is null, or once none of them
  /// served the blob. Throws [BlossomNoServerListException] when there is no
  /// server to try.
  ///
  /// [auth] says which identity the download may be attributed to, see
  /// [AuthPolicy]. Without it the download stays anonymous.
  Future<BlobResponse> getBlob({
    required String sha256,
    AuthPolicy? auth,
    List<String>? serverUrls,
    String? pubkeyToFetchUserServerList,
  }) async {
    final plan = await _readAuthPlan(
      auth: auth,
      sha256: sha256,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
    );

    return _read(
      plan,
      (authorization, servers) => _blossomImpl.getBlob(
        sha256: sha256,
        authorization: authorization,
        serverUrls: servers,
      ),
    );
  }

  /// Downloads a blob directly to a file path (without loading into memory)
  /// For native platforms (Windows, macOS, Linux, Android, iOS): uses actual file system paths
  /// For web: triggers browser download dialog to save the file
  ///
  /// Servers resolve as in [getBlob]. Bytes that do not hash to [sha256] fail
  /// with a [BlossomHashMismatchException] and are not saved.
  /// [auth] says which identity the download may be attributed to, see
  /// [AuthPolicy]. Without it the download stays anonymous.
  Future<void> downloadBlobToFile({
    required String sha256,
    required String outputPath,
    AuthPolicy? auth,
    List<String>? serverUrls,
    String? pubkeyToFetchUserServerList,
  }) async {
    final plan = await _readAuthPlan(
      auth: auth,
      sha256: sha256,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
    );

    return _read(
      plan,
      (authorization, servers) => _blossomImpl.downloadBlobToFile(
        sha256: sha256,
        outputPath: outputPath,
        authorization: authorization,
        serverUrls: servers,
      ),
    );
  }

  /// checks if the blob exists on the server without downloading, useful to check before streaming a video via url \
  /// Servers resolve as in [getBlob].
  ///
  /// returns the url of one server that has the blob e.g. https://myserver.com/hash \
  /// otherwise throws a [BlossomRequestException]
  /// [auth] says which identity the check may be attributed to, see
  /// [AuthPolicy]. Without it the check stays anonymous.
  Future<String> checkBlob({
    required String sha256,
    AuthPolicy? auth,
    List<String>? serverUrls,
    String? pubkeyToFetchUserServerList,
  }) async {
    final plan = await _readAuthPlan(
      auth: auth,
      sha256: sha256,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
    );

    return _read(
      plan,
      (authorization, servers) => _blossomImpl.checkBlob(
        sha256: sha256,
        authorization: authorization,
        serverUrls: servers,
      ),
    );
  }

  /// downloads a blob as a stream, useful for large files like videos \
  /// Servers resolve as in [getBlob]. The stream ends with a
  /// [BlossomHashMismatchException] when the bytes do not hash to [sha256].
  /// [auth] says which identity the download may be attributed to, see
  /// [AuthPolicy]. Without it the download stays anonymous.
  Future<Stream<BlobResponse>> getBlobStream({
    required String sha256,
    AuthPolicy? auth,
    List<String>? serverUrls,
    String? pubkeyToFetchUserServerList,
    int chunkSize = 1024 * 1024, // 1MB chunks,
  }) async {
    final plan = await _readAuthPlan(
      auth: auth,
      sha256: sha256,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
    );

    return _read(
      plan,
      (authorization, servers) => _blossomImpl.getBlobStream(
        sha256: sha256,
        authorization: authorization,
        serverUrls: servers,
        chunkSize: chunkSize,
      ),
    );
  }

  /// list the [pubkey] blobs \
  /// if [serverUrls] is null, the userServerList is fetched from nostr. \
  /// if it has none, or an empty one, throws a [BlossomNoServerListException]
  ///
  /// [auth] says which identity the listing may be attributed to, see
  /// [AuthPolicy]. Without it the listing authorises as the logged-in account
  /// on the servers an [AuthHandler] agrees to, since a server rarely lists a
  /// pubkey's blobs to a stranger, or as a throwaway key when there is no
  /// handler or no account.
  Future<List<BlobDescriptor>> listBlobs({
    required String pubkey,
    List<String>? serverUrls,
    AuthPolicy? auth,
    DateTime? since,
    DateTime? until,
  }) async {
    final plan = await _planAuth(
      auth: auth,
      authorisesByDefault: true,
      operation: "list",
      buildEvent: (owner) =>
          _blossomAuthEvent(content: "List Blobs", pubkey: owner, type: "list"),
      resolveServers: () async => serverUrls ?? await _userServerList(pubkey),
    );

    return _blossomImpl.listBlobs(
      pubkey: pubkey,
      since: since,
      until: until,
      serverUrls: plan.servers,
      authorization: plan.authorization,
    );
  }

  /// delete a blob
  /// if [serverUrls] is null, the userServerList is fetched from nostr. \
  /// if it has none, or an empty one, throws a [BlossomNoServerListException]
  /// [auth] says which identity the deletion may be attributed to, see
  /// [AuthPolicy]. Without it the deletion authorises as the logged-in
  /// account on the servers an [AuthHandler] agrees to, or as a throwaway key
  /// when there is no handler or no account.
  Future<List<BlobDeleteResult>> deleteBlob({
    required String sha256,
    List<String>? serverUrls,
    AuthPolicy? auth,
    String? pubkeyToFetchUserServerList,
  }) async {
    final plan = await _planAuth(
      auth: auth,
      authorisesByDefault: true,
      operation: "delete",
      buildEvent: (pubkey) => _blossomAuthEvent(
        content: "delete",
        pubkey: pubkey,
        type: "delete",
        blobSha256: sha256,
      ),
      resolveServers: () => _resolveWriteServers(
        serverUrls: serverUrls,
        explicitPubkey: pubkeyToFetchUserServerList,
        listOwner: auth?.account?.pubkey,
      ),
    );

    return _blossomImpl.deleteBlob(
      sha256: sha256,
      authorization: plan.authorization,
      serverUrls: plan.servers,
    );
  }

  /// Directly downloads a blob from the url, without blossom
  Future<BlobResponse> directDownload({required Uri url}) {
    return _blossomImpl.directDownload(url: url);
  }

  /// Directly downloads a blob from the url to a file, without blossom
  Future<void> directDownloadToFile({
    required Uri url,
    required String outputPath,
  }) {
    return _blossomImpl.directDownloadToFile(url: url, outputPath: outputPath);
  }

  /// Reports a blob to the server
  /// [sha256] is the hash of the blob
  /// [eventId] is the event id where the blob was mentioned
  /// [reportType] is the type of report, e.g. malware @see nip56
  /// [reportMsg] is the message to send to the server
  /// [serverUrl] server url to report to
  ///
  /// returns the http status code of the server
  /// [auth] says which identity signs the report, see [AuthPolicy]. The
  /// endpoint takes a signed event as its body, so there is nothing to
  /// withhold: [AuthPolicy.never] signs with a throwaway key, which is what an
  /// anonymous report is. Without [auth] the logged-in account signs if an
  /// [AuthHandler] agrees to [serverUrl], or a throwaway key when there is no
  /// handler or no account.
  ///
  /// Throws [BlossomAuthUnavailableException] if [auth] requires an identity
  /// that cannot sign, or the [AuthHandler] keeps a named one from [serverUrl].
  Future<int> report({
    required String sha256,
    required String eventId,
    required String reportType,
    required String reportMsg,
    required String serverUrl,
    AuthPolicy? auth,
  }) async {
    final aborts = _aborts;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final EventSigner signer;
    switch (auth) {
      case null:
        final account = _defaultAccount();
        if (account == null) {
          signer = _throwawaySigner();
        } else if (await _consent(serverUrl, account.pubkey)) {
          signer = account.signer;
        } else {
          throw BlossomAuthUnavailableException(account.pubkey, "report");
        }

      case AuthPolicyNever():
        signer = _throwawaySigner();

      case AuthPolicyRequire(:final account):
        if (!account.signer.canSign() ||
            !await _consent(serverUrl, account.pubkey)) {
          throw BlossomAuthUnavailableException(account.pubkey, "report");
        }
        signer = account.signer;

      case AuthPolicyAllow(:final account):
        // allow never promised a signature, so an account that cannot give one
        // reports anonymously rather than as whoever happens to be logged in
        signer =
            account.signer.canSign() &&
                await _consent(serverUrl, account.pubkey)
            ? account.signer
            : _throwawaySigner();
    }

    final Nip01Event reportEvent = Nip01Event(
      content: reportMsg,
      pubKey: signer.getPublicKey(),
      kind: kReport,
      createdAt: now,
      tags: [
        ["x", sha256, reportType.toLowerCase()],
        ["e", eventId, reportType.toLowerCase()],
        ["server", serverUrl],
      ],
    );

    final signedReport = await signer.sign(reportEvent);
    _throwIfAbortedSince(aborts);

    return _blossomImpl.report(
      sha256: sha256,
      reportEvent: signedReport,
      serverUrl: serverUrl,
    );
  }
}
