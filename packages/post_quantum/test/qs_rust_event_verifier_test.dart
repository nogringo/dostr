import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_post_quantum/ndk_post_quantum.dart';
import 'package:test/test.dart';

void main() {
  group('QsRustEventVerifier', () {
    const level = 44;
    final signer = QsRustEventSigner(
      keypair: QsRustEventSigner.generateKeypair(level: level),
      level: level,
    );
    final verifier = QsRustEventVerifier(level: level);

    Future<Nip01Event> signedNote() => signer.sign(
      Nip01Event(pubKey: '', kind: 1, tags: const [], content: 'hello'),
    );

    test('accepts an event its signer signed', () async {
      final event = await signedNote();

      expect(event.pubKey, signer.getPublicKey());
      expect(event.hasValidId, isTrue);
      expect(await verifier.verify(event), isTrue);
    });
  });
}
