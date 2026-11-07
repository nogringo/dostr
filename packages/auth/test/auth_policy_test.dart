import 'package:ndk_auth/ndk_auth.dart';
import 'package:ndk_signer/ndk_signer.dart';
import 'package:test/test.dart';

class _Signer implements EventSigner {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _account(String pubkey) =>
    Account(type: AccountType.publicKey, pubkey: pubkey, signer: _Signer());

void main() {
  test('policies compare by kind and pubkey, not by account instance', () {
    expect(AuthPolicy.allow(_account('a')), AuthPolicy.allow(_account('a')));
    expect(
      AuthPolicy.allow(_account('a')).hashCode,
      AuthPolicy.allow(_account('a')).hashCode,
    );
    expect(
      AuthPolicy.allow(_account('a')),
      isNot(AuthPolicy.allow(_account('b'))),
    );
    expect(
      AuthPolicy.require(_account('a')),
      isNot(AuthPolicy.require(_account('b'))),
    );
    expect(
      AuthPolicy.allow(_account('a')),
      isNot(AuthPolicy.require(_account('a'))),
    );
    expect(AuthPolicy.allow(_account('a')), isNot(const AuthPolicy.never()));
    expect(const AuthPolicy.never(), const AuthPolicy.never());
  });

  test('canonical names the kind and the pubkey', () {
    expect(const AuthPolicy.never().canonical, 'never');
    expect(AuthPolicy.allow(_account('a')).canonical, 'allow:a');
    expect(AuthPolicy.require(_account('a')).canonical, 'require:a');
    expect(
      AuthPolicy.require(_account('a')).toString(),
      AuthPolicy.require(_account('a')).canonical,
    );
  });

  test('account is null only for never', () {
    final account = _account('a');
    expect(const AuthPolicy.never().account, isNull);
    expect(AuthPolicy.allow(account).account, same(account));
    expect(AuthPolicy.require(account).account, same(account));
  });
}
