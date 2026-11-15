import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

class Nip07Signer implements NostrSigner {
  String? cachedPublicKey;

  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  Nip07Signer({this.cachedPublicKey, int maxConcurrentRequests = 100})
    : assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0');

  @override
  bool canSign() {
    return false;
  }

  @override
  bool get requiresInteractiveSigning => true;

  @override
  bool get requiresSignerNetwork => false;

  @override
  Iterable<String> get signerTransportRelayUrls => const <String>[];

  @override
  Future<String?> decrypt(String msg, String destPubkey) async {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  Future<String?> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  Future<String?> encrypt(String msg, String destPubkey) async {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  Future<String?> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  String getPublicKey() {
    if (cachedPublicKey != null) return cachedPublicKey!;
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  Future<String> getPublicKeyAsync() {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      _pendingRequestsController.stream;

  @override
  List<PendingSignerRequest> get pendingRequests => [];

  @override
  bool cancelRequest(String requestId) => false;

  @override
  Future<void> dispose() async {
    await _pendingRequestsController.close();
  }
}
