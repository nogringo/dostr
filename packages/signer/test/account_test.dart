import 'package:ndk_signer/ndk_signer.dart';
import 'package:test/test.dart';

class _Signer implements EventSigner {
  final requests = [
    PendingSignerRequest(
      id: 'req-001',
      method: SignerMethod.signEvent,
      createdAt: DateTime(2024, 1, 1),
      signerPubkey: 'a',
    ),
  ];
  final cancelled = <String>[];
  bool disposed = false;

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      Stream.value(requests);

  @override
  List<PendingSignerRequest> get pendingRequests => requests;

  @override
  bool cancelRequest(String requestId) {
    cancelled.add(requestId);
    return requestId == 'req-001';
  }

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Account', () {
    late _Signer signer;
    late Account account;

    setUp(() {
      signer = _Signer();
      account = Account(
        type: AccountType.externalSigner,
        pubkey: 'a',
        signer: signer,
      );
    });

    test('pendingRequestsStream delegates to signer', () async {
      expect(await account.pendingRequestsStream.first, same(signer.requests));
    });

    test('pendingRequests delegates to signer', () {
      expect(account.pendingRequests, same(signer.requests));
    });

    test('cancelRequest delegates to signer', () {
      expect(account.cancelRequest('req-001'), isTrue);
      expect(account.cancelRequest('some-request-id'), isFalse);
      expect(signer.cancelled, ['req-001', 'some-request-id']);
    });

    test('dispose delegates to signer', () async {
      await account.dispose();
      expect(signer.disposed, isTrue);
    });
  });
}
