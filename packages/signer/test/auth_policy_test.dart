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

void main() {
  test('toString names the kind and the pubkey', () {
    expect(const AuthPolicy.never().toString(), 'never');
    expect(AuthPolicy.allow(_Signer('a')).toString(), 'allow:a');
    expect(AuthPolicy.require(_Signer('a')).toString(), 'require:a');
  });

  test('signer is null only for never', () {
    final signer = _Signer('a');
    expect(const AuthPolicy.never().signer, isNull);
    expect(AuthPolicy.allow(signer).signer, same(signer));
    expect(AuthPolicy.require(signer).signer, same(signer));
  });
}
