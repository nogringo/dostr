import 'package:test/test.dart';
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_auth/ndk_auth.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

void main() async {
  group('accounts', () {
    KeyPair key0 = Bip340.generatePrivateKey();
    KeyPair key1 = Bip340.generatePrivateKey();

    late Accounts accounts;

    setUp(() async {
      accounts = Accounts(const Bip340EventSignerFactory());
    });

    tearDown(() async {
      await accounts.dispose();
    });

    test('loginPublicKey', () {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginPublicKey(pubkey: key0.publicKey);
      expect(accounts.isLoggedIn, true);
      expect(accounts.cannotSign, true);
      expect(accounts.getPublicKey(), key0.publicKey);
      expect(accounts.getLoggedAccount()!.pubkey, key0.publicKey);
      expect(accounts.hasAccount(key0.publicKey), true);
      accounts.logout();
      expect(accounts.isNotLoggedIn, true);
    });

    test('cannot sign', () {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginPublicKey(pubkey: key0.publicKey);
      expect(accounts.isLoggedIn, true);
      expect(accounts.cannotSign, true);
      expect(accounts.getPublicKey(), key0.publicKey);
      expect(accounts.getLoggedAccount()!.pubkey, key0.publicKey);
      expect(accounts.hasAccount(key0.publicKey), true);
      expect(
        () => accounts.sign(
          Nip01Event(
            pubKey: key0.publicKey,
            kind: Nip01Event.kTextNoteKind,
            tags: [],
            content: "",
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('loginPrivateKey', () {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginPrivateKey(
        pubkey: key0.publicKey,
        privkey: key0.privateKey!,
      );
      expect(accounts.getLoggedAccount()!.pubkey, key0.publicKey);
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);
      accounts.logout();
      expect(accounts.isNotLoggedIn, true);
    });

    test('loginExternalSigner', () {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginExternalSigner(
        signer: Bip340EventSigner(
          privateKey: key0.privateKey,
          publicKey: key0.publicKey,
        ),
      );
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);
      accounts.logout();
      expect(accounts.isNotLoggedIn, true);
    });

    test('remove account', () {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginExternalSigner(
        signer: Bip340EventSigner(
          privateKey: key0.privateKey,
          publicKey: key0.publicKey,
        ),
      );
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);
      accounts.removeAccount(pubkey: key0.publicKey);
      expect(accounts.isNotLoggedIn, true);
    });

    test('do not allow duplicated login', () {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginPrivateKey(
        pubkey: key0.publicKey,
        privkey: key0.privateKey!,
      );
      expect(accounts.getLoggedAccount()!.pubkey, key0.publicKey);
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);
      expect(
        () => accounts.loginPrivateKey(
          pubkey: key0.publicKey,
          privkey: key0.privateKey!,
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        () => accounts.loginPublicKey(pubkey: key0.publicKey),
        throwsA(isA<Exception>()),
      );
      expect(
        () => accounts.loginExternalSigner(
          signer: Bip340EventSigner(
            privateKey: key0.privateKey,
            publicKey: key0.publicKey,
          ),
        ),
        throwsA(isA<Exception>()),
      );
      expect(accounts.getLoggedAccount()!.pubkey, key0.publicKey);
      accounts.logout();
      expect(accounts.isNotLoggedIn, true);
    });

    test('switchAccount', () {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginPrivateKey(
        pubkey: key0.publicKey,
        privkey: key0.privateKey!,
      );
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);
      expect(accounts.hasAccount(key0.publicKey), true);
      expect(accounts.getLoggedAccount()!.pubkey, key0.publicKey);

      accounts.loginPrivateKey(
        pubkey: key1.publicKey,
        privkey: key1.privateKey!,
      );
      expect(accounts.hasAccount(key1.publicKey), true);
      expect(accounts.getLoggedAccount()!.pubkey, key1.publicKey);

      accounts.switchAccount(pubkey: key0.publicKey);
      expect(accounts.hasAccount(key0.publicKey), true);
      expect(accounts.hasAccount(key1.publicKey), true);
      expect(accounts.getLoggedAccount()!.pubkey, key0.publicKey);

      accounts.logout();
      expect(accounts.hasAccount(key0.publicKey), false);
      expect(accounts.hasAccount(key1.publicKey), true);
      expect(accounts.isNotLoggedIn, true);
      expect(accounts.cannotSign, true);
      expect(accounts.getLoggedAccount(), isNull);

      accounts.switchAccount(pubkey: key1.publicKey);
      expect(accounts.hasAccount(key1.publicKey), true);
      expect(accounts.getLoggedAccount()!.pubkey, key1.publicKey);
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);

      expect(
        () => accounts.switchAccount(pubkey: key0.publicKey),
        throwsA(isA<Exception>()),
      );

      accounts.logout();
      expect(accounts.isNotLoggedIn, true);
    });
    test('state Changes Listener', () async {
      final firstAccount = Bip340.generatePrivateKey();
      final secondAccount = Bip340.generatePrivateKey();

      final stream = accounts.authStateChanges;

      final expectation = expectLater(
        stream,
        emitsInOrder([
          predicate<Account?>((a) => a?.pubkey == firstAccount.publicKey),
          predicate<Account?>((a) => a?.pubkey == secondAccount.publicKey),
          predicate<Account?>((a) => a?.pubkey == firstAccount.publicKey),
          predicate<Account?>((a) => a?.pubkey == null),
        ]),
      );

      accounts.loginPrivateKey(
        pubkey: firstAccount.publicKey,
        privkey: firstAccount.privateKey!,
      );

      accounts.loginPublicKey(pubkey: secondAccount.publicKey);

      accounts.switchAccount(pubkey: firstAccount.publicKey);

      accounts.logout();

      await expectation;
    });

    test('accountsStream emits on every change', () async {
      final expectation = expectLater(
        accounts.accountsStream,
        emitsInOrder([
          isEmpty,
          {key0.publicKey: anything},
          {key0.publicKey: anything, key1.publicKey: anything},
          {key1.publicKey: anything},
          isEmpty,
        ]),
      );

      accounts.loginPrivateKey(
        pubkey: key0.publicKey,
        privkey: key0.privateKey!,
      );
      accounts.loginPublicKey(pubkey: key1.publicKey);
      accounts.removeAccount(pubkey: key0.publicKey);
      accounts.removeAccount(pubkey: key1.publicKey);

      await expectation;
    });

    test('accountsStream does not emit when nothing changed', () async {
      final emitted = <Map<String, Account>>[];
      final sub = accounts.accountsStream.listen(emitted.add);

      accounts.loginPublicKey(pubkey: key0.publicKey);
      accounts.removeAccount(pubkey: key1.publicKey);
      accounts.switchAccount(pubkey: key0.publicKey);

      await Future.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted, hasLength(2));
    });

    test('logout and removeAccount notify in the same order', () async {
      for (final removeLoggedAccount in [
        (Accounts a) => a.logout(),
        (Accounts a) => a.removeAccount(pubkey: key0.publicKey),
      ]) {
        final accounts = Accounts(const Bip340EventSignerFactory());
        final order = <String>[];

        accounts.accountsStream.listen((_) => order.add('accounts'));
        accounts.authStateChanges.listen((_) => order.add('auth'));

        accounts.loginPublicKey(pubkey: key0.publicKey);
        await Future.delayed(Duration.zero);
        order.clear();

        removeLoggedAccount(accounts);
        await Future.delayed(Duration.zero);

        expect(order, ['accounts', 'auth']);
        await accounts.dispose();
      }
    });

    test('emitted accounts are unmodifiable snapshots', () async {
      accounts.loginPublicKey(pubkey: key0.publicKey);
      final snapshot = await accounts.accountsStream.first;

      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(() => accounts.accounts.clear(), throwsUnsupportedError);

      accounts.removeAccount(pubkey: key0.publicKey);
      expect(snapshot, hasLength(1));
      expect(accounts.accounts, isEmpty);
    });

    test('accounts is the last emitted snapshot', () async {
      accounts.loginPublicKey(pubkey: key0.publicKey);
      expect(accounts.accounts, same(await accounts.accountsStream.first));

      final before = accounts.accounts;
      accounts.removeAccount(pubkey: key1.publicKey);
      expect(accounts.accounts, same(before));

      accounts.removeAccount(pubkey: key0.publicKey);
      expect(accounts.accounts, isNot(same(before)));
    });

    test("dispose closes stream", () async {
      final stream = accounts.authStateChanges;
      await accounts.dispose();

      await expectLater(stream, emitsDone);
    });
  });
}
