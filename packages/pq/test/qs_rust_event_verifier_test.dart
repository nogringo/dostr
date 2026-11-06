import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_pq/ndk_pq.dart';
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

    test('rejects an event changed after signing', () async {
      final event = await signedNote();
      final forged = event.copyWith(id: event.id, content: 'changed');

      expect(forged.sig, event.sig);
      expect(await verifier.verify(forged), isFalse);
    });
  });
}
