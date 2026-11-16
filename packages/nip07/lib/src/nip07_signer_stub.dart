import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

class Nip07Signer implements NostrSigner {
  /// the pubkey of the extension account this signer signs as
  @override
  final String publicKey;

  final _pendingRequestsController =
      BehaviorSubject<List<PendingSignerRequest>>.seeded([]);

  static const int defaultMaxConcurrentRequests = 100;

  Nip07Signer({
    required this.publicKey,
    int maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) : assert(maxConcurrentRequests > 0, 'maxConcurrentRequests must be > 0');

  /// false: NIP-07 only exists in a browser
  static bool get isAvailable => false;

  static Future<Nip07Signer> connect({
    int maxConcurrentRequests = defaultMaxConcurrentRequests,
  }) async {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  bool get canSign {
    return false;
  }

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    throw UnsupportedError('NIP-07 is not available on this platform');
  }

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
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
