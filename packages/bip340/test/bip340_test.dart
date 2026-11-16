import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:test/test.dart';

void main() {
  final keyPair = Bip340.generatePrivateKey();
  final event = Nip01Event(
    pubkey: keyPair.publicKey,
    kind: 1,
    tags: [],
    content: 'hello',
  );

  test('signEvent produces a signature the verifier accepts', () async {
    final signed = Bip340.signEvent(
      event: event,
      privateKey: keyPair.privateKey!,
    );

    expect(Bip340.verify(signed.id, signed.sig!, keyPair.publicKey), isTrue);
    expect(await Bip340EventVerifier().verify(signed), isTrue);
  });

  test('verifier rejects an event signed by another key', () async {
    final signed = Bip340.signEvent(
      event: event,
      privateKey: Bip340.generatePrivateKey().privateKey!,
    );

    expect(await Bip340EventVerifier().verify(signed), isFalse);
  });

  test('signs and verifies BIP-340 test vector 0 in hex', () {
    const privateKey =
        '0000000000000000000000000000000000000000000000000000000000000003';
    const publicKey =
        'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9';
    final zeros = '00' * 32;
    const signature =
        'e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca8215'
        '25f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0';

    expect(Bip340.getPublicKey(privateKey), publicKey);
    expect(Bip340.sign(zeros, privateKey, auxRand: zeros), signature);
    expect(Bip340.verify(zeros, signature, publicKey), isTrue);
    expect(Bip340.verify(zeros, signature.toUpperCase(), publicKey), isTrue);
  });

  test('rejects a private key out of range', () {
    for (final privateKey in [
      '0' * 64,
      'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
      'z' * 64,
    ]) {
      expect(() => Bip340.getPublicKey(privateKey), throwsFormatException);
      expect(() => Bip340.sign('00' * 32, privateKey), throwsFormatException);
    }
  });

  test('verify returns false on malformed input', () {
    final message = '00' * 32;
    final signature = Bip340.sign(message, keyPair.privateKey!);

    expect(Bip340.verify(message, signature, keyPair.publicKey), isTrue);
    expect(Bip340.verify(message, signature, null), isFalse);
    expect(Bip340.verify(message, signature, 'zz'), isFalse);
    expect(Bip340.verify('0', signature, keyPair.publicKey), isFalse);
    expect(
      Bip340.verify(message, '${signature}00', keyPair.publicKey),
      isFalse,
    );
  });
}
