import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

class _TrackedSigner extends Bip340Signer {
  _TrackedSigner(KeyPair key)
    : super(privateKey: key.privateKey, publicKey: key.publicKey);

  bool disposed = false;

  @override
  Future<void> dispose() {
    disposed = true;
    return super.dispose();
  }
}

Nip01Event _note(String pubkey) => Nip01Event(
  pubkey: pubkey,
  kind: Nip01Event.kTextNoteKind,
  tags: [],
  content: 'hello',
);

void main() async {
  group('accounts', () {
    KeyPair key0 = Bip340.generatePrivateKey();
    KeyPair key1 = Bip340.generatePrivateKey();

    late Accounts accounts;

    setUp(() async {
      accounts = Accounts(const Bip340SignerFactory());
    });

    tearDown(() async {
      await accounts.dispose();
    });

    test('loginPublicKey', () async {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginPublicKey(pubkey: key0.publicKey);
      expect(accounts.isLoggedIn, true);
      expect(accounts.cannotSign, true);
      expect(accounts.loggedPubkey, key0.publicKey);
      expect(accounts.getLoggedAccount()!.publicKey, key0.publicKey);
      expect(accounts.hasAccount(key0.publicKey), true);
      await accounts.logout();
      expect(accounts.isNotLoggedIn, true);
    });

    test('a read-only account cannot sign', () async {
      accounts.loginPublicKey(pubkey: key0.publicKey);
      await expectLater(
        accounts.sign(_note(key0.publicKey)),
        throwsA(
          isA<AccountCannotSignException>().having(
            (e) => e.pubkey,
            'pubkey',
            key0.publicKey,
          ),
        ),
      );
    });

    test('nobody can sign when logged out', () async {
      await expectLater(
        accounts.sign(_note(key0.publicKey)),
        throwsA(
          isA<AccountCannotSignException>().having(
            (e) => e.pubkey,
            'pubkey',
            isNull,
          ),
        ),
      );
    });

    test('loginPrivateKey derives the pubkey', () async {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginPrivateKey(privkey: key0.privateKey!);
      expect(accounts.getLoggedAccount()!.publicKey, key0.publicKey);
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);
      await accounts.logout();
      expect(accounts.isNotLoggedIn, true);
    });

    test('signs as the logged account', () async {
      accounts.loginPrivateKey(privkey: key0.privateKey!);
      final signed = await accounts.sign(_note(key0.publicKey));
      expect(Bip340.verify(signed.id, signed.sig!, key0.publicKey), isTrue);
    });

    test('refuses to sign an event of another pubkey', () async {
      accounts.loginPrivateKey(privkey: key0.privateKey!);
      await expectLater(
        accounts.sign(_note(key1.publicKey)),
        throwsArgumentError,
      );
    });

    test('loginExternalSigner', () async {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginExternalSigner(
        signer: Bip340Signer(
          privateKey: key0.privateKey,
          publicKey: key0.publicKey,
        ),
      );
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);
      await accounts.logout();
      expect(accounts.isNotLoggedIn, true);
    });

    test('addAccount takes the pubkey of the signer, without logging in', () {
      final signer = Bip340Signer(
        privateKey: key0.privateKey,
        publicKey: key0.publicKey,
      );
      accounts.addAccount(signer: signer);
      expect(accounts.accounts, {key0.publicKey: signer});
      expect(accounts.getAccount(key0.publicKey), same(signer));
      expect(accounts.getAccount(key1.publicKey), isNull);
      expect(accounts.isNotLoggedIn, true);
    });

    test('remove account', () async {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginExternalSigner(
        signer: Bip340Signer(
          privateKey: key0.privateKey,
          publicKey: key0.publicKey,
        ),
      );
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);
      await accounts.removeAccount(pubkey: key0.publicKey);
      expect(accounts.isNotLoggedIn, true);
    });

    test('do not allow duplicated accounts', () {
      accounts.loginPrivateKey(privkey: key0.privateKey!);
      final logged = accounts.getLoggedAccount();
      final duplicate = _TrackedSigner(key0);

      final exists = throwsA(
        isA<AccountExistsException>().having(
          (e) => e.pubkey,
          'pubkey',
          key0.publicKey,
        ),
      );
      expect(() => accounts.loginPrivateKey(privkey: key0.privateKey!), exists);
      expect(() => accounts.loginPublicKey(pubkey: key0.publicKey), exists);
      expect(() => accounts.loginExternalSigner(signer: duplicate), exists);
      expect(() => accounts.addAccount(signer: duplicate), exists);

      expect(accounts.getLoggedAccount(), same(logged));
      expect(duplicate.disposed, isFalse);
    });

    test('switchAccount', () async {
      expect(accounts.isNotLoggedIn, true);
      accounts.loginPrivateKey(privkey: key0.privateKey!);
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);
      expect(accounts.hasAccount(key0.publicKey), true);
      expect(accounts.getLoggedAccount()!.publicKey, key0.publicKey);

      accounts.loginPrivateKey(privkey: key1.privateKey!);
      expect(accounts.hasAccount(key1.publicKey), true);
      expect(accounts.getLoggedAccount()!.publicKey, key1.publicKey);

      accounts.switchAccount(pubkey: key0.publicKey);
      expect(accounts.hasAccount(key0.publicKey), true);
      expect(accounts.hasAccount(key1.publicKey), true);
      expect(accounts.getLoggedAccount()!.publicKey, key0.publicKey);

      await accounts.logout();
      expect(accounts.hasAccount(key0.publicKey), false);
      expect(accounts.hasAccount(key1.publicKey), true);
      expect(accounts.isNotLoggedIn, true);
      expect(accounts.cannotSign, true);
      expect(accounts.getLoggedAccount(), isNull);

      accounts.switchAccount(pubkey: key1.publicKey);
      expect(accounts.hasAccount(key1.publicKey), true);
      expect(accounts.getLoggedAccount()!.publicKey, key1.publicKey);
      expect(accounts.isLoggedIn, true);
      expect(accounts.canSign, true);

      expect(
        () => accounts.switchAccount(pubkey: key0.publicKey),
        throwsA(
          isA<UnknownAccountException>().having(
            (e) => e.pubkey,
            'pubkey',
            key0.publicKey,
          ),
        ),
      );

      await accounts.logout();
      expect(accounts.isNotLoggedIn, true);
    });

    test('state Changes Listener', () async {
      final firstAccount = Bip340.generatePrivateKey();
      final secondAccount = Bip340.generatePrivateKey();

      final stream = accounts.authStateChanges;

      final expectation = expectLater(
        stream,
        emitsInOrder([
          isNull,
          predicate<NostrSigner?>(
            (a) => a?.publicKey == firstAccount.publicKey,
          ),
          predicate<NostrSigner?>(
            (a) => a?.publicKey == secondAccount.publicKey,
          ),
          predicate<NostrSigner?>(
            (a) => a?.publicKey == firstAccount.publicKey,
          ),
          isNull,
        ]),
      );

      accounts.loginPrivateKey(privkey: firstAccount.privateKey!);

      accounts.loginPublicKey(pubkey: secondAccount.publicKey);

      accounts.switchAccount(pubkey: firstAccount.publicKey);

      await accounts.logout();

      await expectation;
    });

    test('authStateChanges does not repeat the logged account', () async {
      final emitted = <NostrSigner?>[];
      final sub = accounts.authStateChanges.listen(emitted.add);

      accounts.loginPublicKey(pubkey: key0.publicKey);
      accounts.switchAccount(pubkey: key0.publicKey);

      await Future.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted, [isNull, accounts.getLoggedAccount()]);
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

      accounts.loginPrivateKey(privkey: key0.privateKey!);
      accounts.loginPublicKey(pubkey: key1.publicKey);
      await accounts.removeAccount(pubkey: key0.publicKey);
      await accounts.removeAccount(pubkey: key1.publicKey);

      await expectation;
    });

    test('accountsStream does not emit when nothing changed', () async {
      final emitted = <Map<String, NostrSigner>>[];
      final sub = accounts.accountsStream.listen(emitted.add);

      accounts.loginPublicKey(pubkey: key0.publicKey);
      await accounts.removeAccount(pubkey: key1.publicKey);
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
        final accounts = Accounts(const Bip340SignerFactory());
        final order = <String>[];

        accounts.accountsStream.listen((_) => order.add('accounts'));
        accounts.authStateChanges.listen((_) => order.add('auth'));

        accounts.loginPublicKey(pubkey: key0.publicKey);
        await Future.delayed(Duration.zero);
        order.clear();

        await removeLoggedAccount(accounts);
        await Future.delayed(Duration.zero);

        expect(order, ['accounts', 'auth']);
        await accounts.dispose();
      }
    });

    test('removing an account disposes of its signer', () async {
      final logged = _TrackedSigner(key0);
      final other = _TrackedSigner(key1);
      accounts.addAccount(signer: other);
      accounts.loginExternalSigner(signer: logged);

      await accounts.logout();
      expect(logged.disposed, isTrue);
      expect(other.disposed, isFalse);

      await accounts.removeAccount(pubkey: key1.publicKey);
      expect(other.disposed, isTrue);
    });

    test('dispose disposes of every signer', () async {
      final signers = [_TrackedSigner(key0), _TrackedSigner(key1)];
      for (final signer in signers) {
        accounts.addAccount(signer: signer);
      }

      await accounts.dispose();

      expect(signers.map((s) => s.disposed), everyElement(isTrue));
    });

    test('emitted accounts are unmodifiable snapshots', () async {
      accounts.loginPublicKey(pubkey: key0.publicKey);
      final snapshot = await accounts.accountsStream.first;

      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(() => accounts.accounts.clear(), throwsUnsupportedError);

      await accounts.removeAccount(pubkey: key0.publicKey);
      expect(snapshot, hasLength(1));
      expect(accounts.accounts, isEmpty);
    });

    test('accounts is the last emitted snapshot', () async {
      accounts.loginPublicKey(pubkey: key0.publicKey);
      expect(accounts.accounts, same(await accounts.accountsStream.first));

      final before = accounts.accounts;
      await accounts.removeAccount(pubkey: key1.publicKey);
      expect(accounts.accounts, same(before));

      await accounts.removeAccount(pubkey: key0.publicKey);
      expect(accounts.accounts, isNot(same(before)));
    });

    test("dispose closes stream", () async {
      final expectation = expectLater(
        accounts.authStateChanges,
        emitsInOrder([isNull, emitsDone]),
      );
      await accounts.dispose();

      await expectation;
    });
  });
}
