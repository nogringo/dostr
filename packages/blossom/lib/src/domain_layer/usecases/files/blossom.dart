import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dostr_blossom_url/dostr_blossom_url.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:http/http.dart' as http;

import '../../../data_layer/http/operation_abort.dart';
import '../../../data_layer/io/file_io_platform.dart';
import '../../../data_layer/repositories/blossom/http_blossom_repository.dart';
import '../../entities/blob_upload_progress.dart';
import '../../entities/blossom_authorization.dart';
import '../../entities/blossom_blobs.dart';
import '../../entities/blossom_hash_mismatch_exception.dart';
import '../../entities/blossom_request_exception.dart';
import '../../entities/blossom_strategies.dart';
import '../../entities/file_hash_progress.dart';
import '../../repositories/blossom_repository.dart';
import 'blossom_exceptions.dart';

/// The servers in [pubkey]'s Blossom server list (kind 10063, BUD-03), or
/// null when they have none.
typedef BlossomServerListResolver =
    Future<List<String>?> Function(String pubkey);

/// Builds the kind 24242 event an operation authorises itself with as
/// [pubkey].
typedef _AuthEventBuilder = Nip01Event Function(String pubkey);

/// [servers] less those an [AuthHandler] keeps an upfront authorization from
typedef _ServerFilter =
    Future<List<BlossomServerUrl>> Function(List<BlossomServerUrl> servers);

/// The servers of [servers] that [BlossomServerUrl.tryParse] accepts,
/// normalized, less those [seen] or an earlier one already names. The ones it
/// keeps join [seen].
List<BlossomServerUrl> _distinctServers(
  Iterable<String> servers, [
  Set<BlossomServerUrl>? seen,
]) {
  final named = seen ?? {};
  return [
    for (final server in servers.map(BlossomServerUrl.tryParse).nonNulls)
      if (named.add(server)) server,
  ];
}

/// The servers a call named, as [_distinctServers] keeps them, or a
/// [BlossomNoServerListException] when it keeps none
List<BlossomServerUrl> _givenServers(Iterable<String> servers) {
  final kept = _distinctServers(servers);
  if (kept.isEmpty) throw const BlossomNoServerListException();
  return kept;
}

/// The sha256 of [data], which must be [contentLength] bytes long, reported
/// as it is read
Stream<FileHashProgress> _hashOf(
  Stream<List<int>> data,
  int contentLength,
) async* {
  late Digest digest;
  final hashing = sha256.startChunkedConversion(
    ChunkedConversionSink<Digest>.withCallback(
      (digests) => digest = digests.single,
    ),
  );
  var processedBytes = 0;
  yield FileHashProgress(processedBytes: 0, totalBytes: contentLength);
  await for (final chunk in data) {
    hashing.add(chunk);
    processedBytes += chunk.length;
    yield FileHashProgress(
      processedBytes: processedBytes,
      totalBytes: contentLength,
    );
  }
  hashing.close();
  if (processedBytes != contentLength) {
    throw ArgumentError.value(
      contentLength,
      'contentLength',
      'is not the $processedBytes bytes openRead read',
    );
  }
  yield FileHashProgress(
    processedBytes: processedBytes,
    totalBytes: contentLength,
    isComplete: true,
    hash: digest.toString(),
  );
}

/// What one blossom operation does about its authorization, and the servers
/// it may talk to.
class _BlossomAuthPlan {
  final BlossomAuthorization authorization;

  /// the resolved servers, less those an [AuthHandler] kept an upfront
  /// authorization from
  final List<BlossomServerUrl> servers;

  /// the servers to try once none of [servers] served the operation, resolved
  /// only then and filtered the same way, null when there are none
  final Future<List<BlossomServerUrl>> Function()? nextServers;

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
///
/// Every operation takes an `abortTrigger`. Once it completes, with a value
/// or an error, that operation ends with a `RequestAbortedException` (from
/// `package:http`) as [abortPending] would end it, and the others go on.
class Blossom {
  /// kind of the authorization events [BUD-11]
  static const kBlossomAuthorization = 24242;

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

  final BlossomServerListResolver? _getUserServerList;
  final BlossomRepository _blossomImpl;
  final AuthAccounts? _accounts;
  final LocalSignerFactory? _signerFactory;
  final AuthHandler? _authHandler;
  final Duration _authExpiration;

  /// the client this instance made, which [close] closes
  final http.Client? _ownedClient;

  /// [accounts] gives the logged-in account, [signerFactory] makes the
  /// throwaway keys, and [getUserServerList] reads a user's kind 10063 list.
  /// A read needs none of them: without [accounts] nobody is logged in, and
  /// without [getUserServerList] nobody has a list. An operation that signs
  /// with a throwaway key throws a [StateError] without [signerFactory].
  ///
  /// It talks to the servers over HTTP with [httpClient], or with a client of
  /// its own that [close] closes. [blossomRepository] replaces that HTTP
  /// layer, and the two cannot be given together.
  ///
  /// [authExpiration] is how long a signed kind 24242 event stays valid. An
  /// operation that outlives it signs a new one when a server refuses the
  /// expired one.
  factory Blossom({
    AuthAccounts? accounts,
    LocalSignerFactory? signerFactory,
    BlossomServerListResolver? getUserServerList,
    AuthHandler? authHandler,
    http.Client? httpClient,
    BlossomRepository? blossomRepository,
    Duration authExpiration = defaultAuthExpiration,
  }) {
    if (httpClient != null && blossomRepository != null) {
      throw ArgumentError(
        'Blossom takes an httpClient or a blossomRepository, not both',
      );
    }
    final ownedClient = httpClient == null && blossomRepository == null
        ? http.Client()
        : null;
    return Blossom._(
      accounts: accounts,
      signerFactory: signerFactory,
      getUserServerList: getUserServerList,
      authHandler: authHandler,
      blossomRepository:
          blossomRepository ??
          HttpBlossomRepository(
            client: httpClient ?? ownedClient!,
            fileIO: createFileIO(),
          ),
      ownedClient: ownedClient,
      authExpiration: authExpiration,
    );
  }

  Blossom._({
    required AuthAccounts? accounts,
    required LocalSignerFactory? signerFactory,
    required BlossomServerListResolver? getUserServerList,
    required AuthHandler? authHandler,
    required BlossomRepository blossomRepository,
    required http.Client? ownedClient,
    required Duration authExpiration,
  }) : _accounts = accounts,
       _signerFactory = signerFactory,
       _getUserServerList = getUserServerList,
       _authHandler = authHandler,
       _blossomImpl = blossomRepository,
       _ownedClient = ownedClient,
       _authExpiration = authExpiration;

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

  /// Ends the operations in flight, as [abortPending] does, and closes the
  /// HTTP client this instance made. A client given to the constructor stays
  /// open: it is the caller's to close. This instance is unusable afterwards.
  void close() {
    abortPending();
    _ownedClient?.close();
  }

  /// An operation makes its abort when it starts, and checks it after it
  /// waited on something other than a request, such as a signer.
  OperationAbort _abortFor(Future<void>? trigger) =>
      OperationAbort(() => _aborts, trigger);

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
      pubkey: pubkey,
      kind: kBlossomAuthorization,
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
  NostrSigner? _defaultAccount() {
    final account = _accounts?.getLoggedAccount();
    return _authHandler != null && account != null && account.canSign
        ? account
        : null;
  }

  /// Whether [serverUrl] may see [pubkey]. A failing [AuthHandler] says no.
  Future<bool> _consent(String serverUrl, String pubkey) async {
    final handler = _authHandler;
    if (handler == null) return true;
    try {
      return await handler(serverUrl, pubkey);
    } catch (_) {
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
    required Future<List<BlossomServerUrl>> Function() resolveServers,
    required OperationAbort abort,
    Future<List<BlossomServerUrl>> Function()? resolveNextServers,
  }) async {
    final fallback = authorisesByDefault ? _defaultAccount() : null;
    final throwaway = auth == null && authorisesByDefault && fallback == null;
    final policy =
        auth ??
        (authorisesByDefault
            ? AuthPolicy.require(fallback ?? _throwawaySigner())
            : const AuthPolicy.never());

    var resolveNext = resolveNextServers;
    _ServerFilter admit = (servers) async => servers;
    final List<BlossomServerUrl> servers;
    final Future<BlossomAuthorization> Function(_AuthEventBuilder) authorize;
    switch (policy) {
      case AuthPolicyNever():
        servers = await resolveServers();
        authorize = (_) async => const BlossomAuthorization.none();

      case AuthPolicyRequire(signer: final account):
        if (!account.canSign) {
          throw BlossomAuthUnavailableException(account.publicKey, operation);
        }
        if (!throwaway) {
          admit = (servers) => _serversAllowing(servers, account.publicKey);
        }
        var admitted = await admit(await resolveServers());
        final next = resolveNext;
        if (admitted.isEmpty && next != null) {
          admitted = await admit(await next());
          resolveNext = null;
        }
        if (admitted.isEmpty) {
          throw BlossomAuthUnavailableException(account.publicKey, operation);
        }
        servers = admitted;
        Future<Nip01Event> sign(_AuthEventBuilder build) =>
            account.sign(build(account.publicKey));
        authorize = (build) async => BlossomAuthorization.upfront(
          await sign(build),
          renew: () => sign(build),
        );

      case AuthPolicyAllow(signer: final account):
        servers = await resolveServers();
        // allow never promised a signature, so an account that cannot give one
        // behaves as never() rather than failing the operation
        authorize = (build) async => account.canSign
            ? BlossomAuthorization.onRefusal(
                () => account.sign(build(account.publicKey)),
                consent: _authHandler == null
                    ? null
                    : (serverUrl) => _consent(serverUrl, account.publicKey),
              )
            : const BlossomAuthorization.none();
    }
    final authorization = await authorize(buildEvent);
    abort.throwIfAborted();
    final next = resolveNext;
    return _BlossomAuthPlan(
      authorization,
      servers,
      authorize,
      nextServers: next == null ? null : () async => admit(await next()),
    );
  }

  Future<List<BlossomServerUrl>> _serversAllowing(
    List<BlossomServerUrl> servers,
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
  /// the blob, or right away when [serverUrls] names no server. Unlike a
  /// write, a read is about somebody else's blob as often as not, so it never
  /// guesses whose list to read.
  Future<_BlossomAuthPlan> _readAuthPlan({
    required AuthPolicy? auth,
    required String sha256,
    required List<String>? serverUrls,
    required String? pubkeyToFetchUserServerList,
    required OperationAbort abort,
  }) {
    final owner = pubkeyToFetchUserServerList;
    final tried = <BlossomServerUrl>{};
    var listRead = false;
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
        final given = _distinctServers(serverUrls ?? const [], tried);
        if (given.isNotEmpty) return given;
        if (owner == null) throw const BlossomNoServerListException();
        listRead = true;
        return _distinctServers(await _userServerList(owner), tried);
      },
      resolveNextServers: serverUrls == null || owner == null
          ? null
          : () async => listRead
                ? const []
                : _distinctServers(await _serverListOf(owner) ?? [], tried),
      abort: abort,
    );
  }

  /// Runs [read] on the servers [plan] starts with, then on its next ones if
  /// none of the first served the blob.
  Future<T> _read<T>(
    _BlossomAuthPlan plan,
    OperationAbort abort,
    Future<T> Function(
      BlossomAuthorization authorization,
      List<BlossomServerUrl> servers,
    )
    read,
  ) async {
    try {
      return await read(plan.authorization, plan.servers);
    } on BlossomRequestException catch (first) {
      final nextServers = plan.nextServers;
      if (nextServers == null) rethrow;
      final servers = await nextServers();
      abort.throwIfAborted();
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
    required OperationAbort abort,
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
        listOwner: auth?.signer?.publicKey,
      ),
      abort: abort,
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

  /// The servers a write talks to, each once: an explicit list, else an
  /// explicit pubkey's kind 10063 list, else the identity the policy names,
  /// else the logged-in account's.
  ///
  /// That last fallback applies even under [AuthPolicy.never]. Reading a
  /// public kind 10063 from relays tells the blossom servers nothing, and
  /// never() is a statement about the `Authorization` header, not about which
  /// nostr list may be read.
  Future<List<BlossomServerUrl>> _resolveWriteServers({
    required List<String>? serverUrls,
    required String? explicitPubkey,
    required String? listOwner,
  }) async {
    if (serverUrls != null) return _givenServers(serverUrls);

    final owner =
        explicitPubkey ?? listOwner ?? _accounts?.getLoggedAccount()?.publicKey;
    if (owner == null) throw const BlossomNoServerListException();
    return _userServerList(owner);
  }

  /// [pubkey]'s server list as [getUserServerList] reads it, null without one
  Future<List<String>?> _serverListOf(String pubkey) async =>
      await _getUserServerList?.call(pubkey);

  /// [pubkey]'s servers, normalized and each once, or a
  /// [BlossomNoServerListException] when it has none
  Future<List<BlossomServerUrl>> _userServerList(String pubkey) async {
    final servers = _distinctServers(await _serverListOf(pubkey) ?? []);
    if (servers.isEmpty) throw BlossomNoServerListException(pubkey);
    return servers;
  }

  /// A fresh key, for something that has to be signed but names nobody.
  NostrSigner _throwawaySigner() {
    final factory = _signerFactory;
    if (factory == null) {
      throw StateError(
        'Blossom signs with a throwaway key here, and has no signerFactory '
        'to make one: give it one, or name the identity with auth',
      );
    }
    return factory.createWithNewKeyPair();
  }

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
    Future<void>? abortTrigger,
  }) async {
    final plan = await _uploadAuthPlan(
      auth: auth,
      sha256: sha256,
      media: serverMediaOptimisation,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
      abort: _abortFor(abortTrigger),
    );

    return _blossomImpl.checkUpload(
      sha256: sha256,
      contentLength: contentLength,
      serverUrls: plan.servers,
      authorization: plan.authorization,
      contentType: contentType,
      serverMediaOptimisation: serverMediaOptimisation,
      abortTrigger: abortTrigger,
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
    Future<void>? abortTrigger,
  }) async {
    /// sha256 of the data
    final dataSha256 = precomputedSha256 ?? sha256.convert(data).toString();

    final plan = await _uploadAuthPlan(
      auth: auth,
      sha256: dataSha256,
      media: serverMediaOptimisation,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
      abort: _abortFor(abortTrigger),
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
      abortTrigger: abortTrigger,
    );

    final done = await stream.last;

    return done.completedUploads;
  }

  /// Upload a blob from a file path, read in chunks so a large file is never
  /// held whole in memory.
  /// Native platforms only (Windows, macOS, Linux, Android, iOS): a browser
  /// has no file paths, so there the stream fails with an [UnsupportedError].
  /// Upload the file the app picked with [uploadBlobFromStream] instead.
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
    Future<void>? abortTrigger,
  }) => _uploadWithProgress(
    hash: () => _blossomImpl.computeFileHash(filePath),
    upload: (plan) => _blossomImpl.uploadBlobFromFile(
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
      abortTrigger: abortTrigger,
    ),
    serverUrls: serverUrls,
    strategy: strategy,
    serverMediaOptimisation: serverMediaOptimisation,
    auth: auth,
    pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
    precomputedSha256: precomputedSha256,
    abortTrigger: abortTrigger,
  );

  /// Uploads the [contentLength] bytes [openRead] reads, without holding them
  /// in memory, on every platform. It takes what a file picker gives, such as
  /// `PlatformFile.readAsByteStream` of `file_picker` or `XFile.openRead`.
  ///
  /// [openRead] must read the same bytes from the start on every call: it is
  /// called once to hash them, unless [precomputedSha256] is given, then once
  /// per server, and once more when a server asks the upload to authorise
  /// itself. Hashing fails with an [ArgumentError] when it reads another
  /// length than [contentLength].
  ///
  /// The other parameters and the progress are those of
  /// [uploadBlobFromFile].
  Stream<BlobUploadProgress> uploadBlobFromStream({
    required Stream<List<int>> Function() openRead,
    required int contentLength,
    List<String>? serverUrls,
    String? contentType,
    UploadStrategy strategy = UploadStrategy.mirrorAfterSuccess,
    bool serverMediaOptimisation = false,
    AuthPolicy? auth,
    String? pubkeyToFetchUserServerList,
    String? precomputedSha256,
    Future<void>? abortTrigger,
  }) => _uploadWithProgress(
    hash: () => _hashOf(openRead(), contentLength),
    upload: (plan) => _blossomImpl.uploadBlob(
      dataStreamFactory: openRead,
      contentLength: contentLength,
      serverUrls: plan.servers,
      authorization: plan.authorization,
      contentType: contentType,
      strategy: strategy,
      serverMediaOptimisation: serverMediaOptimisation,
      mirrorAuthorization: _mirrorAuthorization(
        plan,
        media: serverMediaOptimisation,
      ),
      abortTrigger: abortTrigger,
    ),
    serverUrls: serverUrls,
    strategy: strategy,
    serverMediaOptimisation: serverMediaOptimisation,
    auth: auth,
    pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
    precomputedSha256: precomputedSha256,
    abortTrigger: abortTrigger,
  );

  /// Hashes with [hash] unless [precomputedSha256] is given, then runs
  /// [upload] on the servers and authorization the hash resolves, the hashing
  /// taking the first share of the progress.
  Stream<BlobUploadProgress> _uploadWithProgress({
    required Stream<FileHashProgress> Function() hash,
    required Stream<BlobUploadProgress> Function(_BlossomAuthPlan plan) upload,
    required List<String>? serverUrls,
    required UploadStrategy strategy,
    required bool serverMediaOptimisation,
    required AuthPolicy? auth,
    required String? pubkeyToFetchUserServerList,
    required String? precomputedSha256,
    required Future<void>? abortTrigger,
  }) async* {
    final abort = _abortFor(abortTrigger);
    String? blobHash = precomputedSha256;
    final hashes = blobHash == null;

    if (hashes) {
      // the servers are not resolved yet, so assume the mirrors take place:
      // progress may then skip ahead, but never back
      final phases = [
        UploadPhase.hashing,
        UploadPhase.uploading,
        if (strategy == UploadStrategy.mirrorAfterSuccess &&
            (serverUrls == null || _distinctServers(serverUrls).length > 1))
          UploadPhase.mirroring,
      ];
      await for (final hashProgress in hash()) {
        abort.throwIfAborted();
        yield BlobUploadProgress(
          sentBytes: hashProgress.processedBytes,
          totalBytes: hashProgress.totalBytes,
          completedUploads: const [],
          phase: UploadPhase.hashing,
          phases: phases,
          progressPhase: hashProgress.progress,
        );

        if (hashProgress.isComplete && hashProgress.hash != null) {
          blobHash = hashProgress.hash;
        }
      }

      if (blobHash == null) {
        throw StateError('hashing ended without giving the hash');
      }
    }
    abort.throwIfAborted();

    final plan = await _uploadAuthPlan(
      auth: auth,
      sha256: blobHash,
      media: serverMediaOptimisation,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
      abort: abort,
    );

    final uploading = upload(plan);
    yield* hashes
        ? uploading.map(
            (progress) =>
                progress.withPhases([UploadPhase.hashing, ...progress.phases]),
          )
        : uploading;
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
  /// Throws a [FormatException] if no SHA256 hash is detected in the URL, and
  /// a [BlossomNoServerListException] if [targetServerUrls] names no server
  /// [BlossomServerUrl.tryParse] accepts.
  Future<List<BlobUploadResult>> mirrorToServers({
    required Uri blossomUrl,
    required List<String> targetServerUrls,
    AuthPolicy? auth,
    Future<void>? abortTrigger,
  }) async {
    final sha256Match = sha256Regex.firstMatch(blossomUrl.toString());
    if (sha256Match == null) {
      throw FormatException('No sha256 in the blob url', blossomUrl.toString());
    }

    final sha256 = sha256Match.group(1)!;

    final plan = await _planAuth(
      auth: auth,
      authorisesByDefault: true,
      operation: "upload",
      buildEvent: _writeEvent("upload", sha256),
      resolveServers: () async => _givenServers(targetServerUrls),
      abort: _abortFor(abortTrigger),
    );

    // Mirror to all target servers
    final results = await Future.wait(
      plan.servers.map(
        (serverUrl) => _blossomImpl.mirrorToServer(
          fileUrl: blossomUrl.toString(),
          serverUrl: serverUrl,
          sha256: sha256,
          authorization: plan.authorization,
          abortTrigger: abortTrigger,
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
  /// list (kind 10063) is read when [serverUrls] names no server, or once none
  /// of them served the blob. Throws [BlossomNoServerListException] when there
  /// is no server to try.
  ///
  /// [auth] says which identity the download may be attributed to, see
  /// [AuthPolicy]. Without it the download stays anonymous.
  Future<BlobResponse> getBlob({
    required String sha256,
    AuthPolicy? auth,
    List<String>? serverUrls,
    String? pubkeyToFetchUserServerList,
    Future<void>? abortTrigger,
  }) async {
    final abort = _abortFor(abortTrigger);
    final plan = await _readAuthPlan(
      auth: auth,
      sha256: sha256,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
      abort: abort,
    );

    return _read(
      plan,
      abort,
      (authorization, servers) => _blossomImpl.getBlob(
        sha256: sha256,
        authorization: authorization,
        serverUrls: servers,
        abortTrigger: abortTrigger,
      ),
    );
  }

  /// Downloads a blob directly to a file path (without loading into memory)
  /// For native platforms (Windows, macOS, Linux, Android, iOS): uses actual file system paths
  /// For web: triggers browser download dialog to save the file, named [outputPath]
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
    Future<void>? abortTrigger,
  }) async {
    final abort = _abortFor(abortTrigger);
    final plan = await _readAuthPlan(
      auth: auth,
      sha256: sha256,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
      abort: abort,
    );

    return _read(
      plan,
      abort,
      (authorization, servers) => _blossomImpl.downloadBlobToFile(
        sha256: sha256,
        outputPath: outputPath,
        authorization: authorization,
        serverUrls: servers,
        abortTrigger: abortTrigger,
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
    Future<void>? abortTrigger,
  }) async {
    final abort = _abortFor(abortTrigger);
    final plan = await _readAuthPlan(
      auth: auth,
      sha256: sha256,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
      abort: abort,
    );

    return _read(
      plan,
      abort,
      (authorization, servers) => _blossomImpl.checkBlob(
        sha256: sha256,
        authorization: authorization,
        serverUrls: servers,
        abortTrigger: abortTrigger,
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
    Future<void>? abortTrigger,
  }) async {
    final abort = _abortFor(abortTrigger);
    final plan = await _readAuthPlan(
      auth: auth,
      sha256: sha256,
      serverUrls: serverUrls,
      pubkeyToFetchUserServerList: pubkeyToFetchUserServerList,
      abort: abort,
    );

    return _read(
      plan,
      abort,
      (authorization, servers) => _blossomImpl.getBlobStream(
        sha256: sha256,
        authorization: authorization,
        serverUrls: servers,
        chunkSize: chunkSize,
        abortTrigger: abortTrigger,
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
    Future<void>? abortTrigger,
  }) async {
    final plan = await _planAuth(
      auth: auth,
      authorisesByDefault: true,
      operation: "list",
      buildEvent: (owner) =>
          _blossomAuthEvent(content: "List Blobs", pubkey: owner, type: "list"),
      resolveServers: () async => serverUrls == null
          ? await _userServerList(pubkey)
          : _givenServers(serverUrls),
      abort: _abortFor(abortTrigger),
    );

    return _blossomImpl.listBlobs(
      pubkey: pubkey,
      since: since,
      until: until,
      serverUrls: plan.servers,
      authorization: plan.authorization,
      abortTrigger: abortTrigger,
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
    Future<void>? abortTrigger,
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
        listOwner: auth?.signer?.publicKey,
      ),
      abort: _abortFor(abortTrigger),
    );

    return _blossomImpl.deleteBlob(
      sha256: sha256,
      authorization: plan.authorization,
      serverUrls: plan.servers,
      abortTrigger: abortTrigger,
    );
  }

  /// Directly downloads a blob from the url, without blossom
  Future<BlobResponse> directDownload({
    required Uri url,
    Future<void>? abortTrigger,
  }) {
    return _blossomImpl.directDownload(url: url, abortTrigger: abortTrigger);
  }

  /// Directly downloads a blob from the url to a file, without blossom
  Future<void> directDownloadToFile({
    required Uri url,
    required String outputPath,
    Future<void>? abortTrigger,
  }) {
    return _blossomImpl.directDownloadToFile(
      url: url,
      outputPath: outputPath,
      abortTrigger: abortTrigger,
    );
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
  /// Throws a [FormatException], before anything is signed, if [serverUrl] is
  /// not a Blossom server url.
  Future<int> report({
    required String sha256,
    required String eventId,
    required String reportType,
    required String reportMsg,
    required String serverUrl,
    AuthPolicy? auth,
    Future<void>? abortTrigger,
  }) async {
    final server = BlossomServerUrl.parse(serverUrl);
    final abort = _abortFor(abortTrigger);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final NostrSigner signer;
    switch (auth) {
      case null:
        final account = _defaultAccount();
        if (account == null) {
          signer = _throwawaySigner();
        } else if (await _consent(server, account.publicKey)) {
          signer = account;
        } else {
          throw BlossomAuthUnavailableException(account.publicKey, "report");
        }

      case AuthPolicyNever():
        signer = _throwawaySigner();

      case AuthPolicyRequire(signer: final account):
        if (!account.canSign || !await _consent(server, account.publicKey)) {
          throw BlossomAuthUnavailableException(account.publicKey, "report");
        }
        signer = account;

      case AuthPolicyAllow(signer: final account):
        // allow never promised a signature, so an account that cannot give one
        // reports anonymously rather than as whoever happens to be logged in
        signer = account.canSign && await _consent(server, account.publicKey)
            ? account
            : _throwawaySigner();
    }

    final Nip01Event reportEvent = Nip01Event(
      content: reportMsg,
      pubkey: signer.publicKey,
      kind: kReport,
      createdAt: now,
      tags: [
        ["x", sha256, reportType.toLowerCase()],
        ["e", eventId, reportType.toLowerCase()],
        ["server", server],
      ],
    );

    final signedReport = await signer.sign(reportEvent);
    abort.throwIfAborted();

    return _blossomImpl.report(
      sha256: sha256,
      reportEvent: signedReport,
      serverUrl: server,
      abortTrigger: abortTrigger,
    );
  }
}
