import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

void main() {
  final keyPair = Bip340.generatePrivateKey();
  final event = Nip01Event(
    pubKey: keyPair.publicKey,
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
    expect(await Bip340EventVerifier(useIsolate: false).verify(signed), isTrue);
  });

  test('verifier rejects an event signed by another key', () async {
    final signed = Bip340.signEvent(
      event: event,
      privateKey: Bip340.generatePrivateKey().privateKey!,
    );

    expect(
      await Bip340EventVerifier(useIsolate: false).verify(signed),
      isFalse,
    );
  });
}
