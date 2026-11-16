import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

/// A wrapper signer that adds a delay to simulate slow signing
/// (like NIP-46, NIP-55, etc.) where user interaction is required.
class MockSlowSigner implements NostrSigner {
  final NostrSigner _innerSigner;
  final Duration _delay;

  MockSlowSigner({required NostrSigner innerSigner, required Duration delay})
    : _innerSigner = innerSigner,
      _delay = delay;

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    await Future.delayed(_delay);
    return _innerSigner.sign(event);
  }

  @override
  String getPublicKey() => _innerSigner.getPublicKey();

  @override
  bool get canSign => _innerSigner.canSign;

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) => throw UnimplementedError();

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) => throw UnimplementedError();

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) async {
    await Future.delayed(_delay);
    return _innerSigner.encryptNip44(
      plaintext: plaintext,
      recipientPubkey: recipientPubkey,
    );
  }

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    await Future.delayed(_delay);
    return _innerSigner.decryptNip44(
      ciphertext: ciphertext,
      senderPubkey: senderPubkey,
    );
  }

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      _innerSigner.pendingRequestsStream;

  @override
  List<PendingSignerRequest> get pendingRequests =>
      _innerSigner.pendingRequests;

  @override
  bool cancelRequest(String requestId) => _innerSigner.cancelRequest(requestId);

  @override
  Future<void> dispose() => _innerSigner.dispose();
}
