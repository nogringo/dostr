import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

class _Signer implements NostrSigner {
  _Signer(this.pubkey);

  final String pubkey;

  @override
  String get publicKey => pubkey;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _account(String pubkey) => Account(_Signer(pubkey));

void main() {
  test('toString names the kind and the pubkey', () {
    expect(const AuthPolicy.never().toString(), 'never');
    expect(AuthPolicy.allow(_account('a')).toString(), 'allow:a');
    expect(AuthPolicy.require(_account('a')).toString(), 'require:a');
  });

  test('account is null only for never', () {
    final account = _account('a');
    expect(const AuthPolicy.never().account, isNull);
    expect(AuthPolicy.allow(account).account, same(account));
    expect(AuthPolicy.require(account).account, same(account));
  });
}
