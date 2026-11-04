import 'dart:async';

import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import 'mock_relay.dart';

/// the only signature [FakeVerifier] accepts
final String fakeSig = 'f' * 128;

final String alice = 'a' * 64;
final String bob = 'b' * 64;

/// Signs with [fakeSig], whatever the event.
class FakeSigner extends EventSigner {
  FakeSigner(this.publicKey, {this.signable = true});

  final String publicKey;
  bool signable;
  int signatures = 0;

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    signatures++;
    return event.copyWith(sig: fakeSig);
  }

  @override
  String getPublicKey() => publicKey;

  @override
  bool canSign() => signable;

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      Stream.value(const []);

  @override
  List<PendingSignerRequest> get pendingRequests => const [];

  @override
  bool cancelRequest(String requestId) => false;

  @override
  Future<void> dispose() async {}

  @override
  Future<String?> decrypt(String msg, String destPubKey) =>
      throw UnimplementedError();

  @override
  Future<String?> encrypt(String msg, String destPubKey) =>
      throw UnimplementedError();

  @override
  Future<String?> encryptNip44({
    required String plaintext,
    required String recipientPubKey,
  }) => throw UnimplementedError();

  @override
  Future<String?> decryptNip44({
    required String ciphertext,
    required String senderPubKey,
  }) => throw UnimplementedError();
}

/// Accepts [fakeSig] and nothing else.
class FakeVerifier implements EventVerifier {
  int verifications = 0;

  @override
  Future<bool> verify(Nip01Event event) async {
    verifications++;
    return event.sig == fakeSig;
  }
}

class FakeAuthAccounts implements AuthAccounts {
  @override
  final Map<String, Account> accounts = {};

  String? loggedPubkey;

  @override
  Account? getLoggedAccount() => accounts[loggedPubkey];
}

Account fakeAccount(String pubkey, {bool canSign = true}) => Account(
  type: AccountType.privateKey,
  pubkey: pubkey,
  signer: FakeSigner(pubkey, signable: canSign),
);

Nip01Event signedEvent({
  String? pubKey,
  int kind = 1,
  String content = '',
  List<List<String>> tags = const [],
  int createdAt = 0,
}) => Nip01Event(
  pubKey: pubKey ?? alice,
  kind: kind,
  tags: tags,
  content: content,
  createdAt: createdAt,
).copyWith(sig: fakeSig);

RelayManager newRelayManager({
  AuthAccounts? accounts,
  AuthHandler? authHandler,
  NostrTransportFactory? transportFactory,
}) => RelayManager(
  globalState: GlobalState(),
  nostrTransportFactory:
      transportFactory ??
      WebSocketClientNostrTransportFactory(pingInterval: null),
  accounts: accounts,
  authHandler: authHandler,
);

/// Starts a [MockRelay] for the current test and stops it afterwards.
Future<MockRelay> startRelay({
  bool requireAuthForRequests = false,
  bool requireAuthForEvents = false,
  bool challengeOnConnect = true,
  bool answerRequests = true,
  bool answerEvents = true,
  String? rejectEventsWith,
}) async {
  final relay = MockRelay(
    requireAuthForRequests: requireAuthForRequests,
    requireAuthForEvents: requireAuthForEvents,
    challengeOnConnect: challengeOnConnect,
    answerRequests: answerRequests,
    answerEvents: answerEvents,
    rejectEventsWith: rejectEventsWith,
  );
  await relay.start();
  addTearDown(relay.stop);
  return relay;
}

/// Waits until [condition] holds, failing the test after [timeout].
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
