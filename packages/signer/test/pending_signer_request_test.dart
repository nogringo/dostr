import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

void main() {
  final createdAt = DateTime(2024, 1, 1);

  group('PendingSignerRequest', () {
    test('a signature holds its event', () {
      final event = Nip01Event(pubkey: 'a', kind: 1, content: 'hi');
      final request = PendingSignRequest(
        id: 'req-001',
        createdAt: createdAt,
        signerPubkey: 'a',
        event: event,
      );

      expect(request.event, same(event));
    });

    test('an encryption names its scheme and recipient', () {
      final nip04 = PendingEncryptRequest.nip04(
        id: 'req-002',
        createdAt: createdAt,
        signerPubkey: 'a',
        plaintext: 'hello',
        recipientPubkey: 'b',
      );
      final nip44 = PendingEncryptRequest.nip44(
        id: 'req-003',
        createdAt: createdAt,
        signerPubkey: 'a',
        plaintext: 'hello',
        recipientPubkey: 'b',
      );

      expect(nip04.scheme, EncryptionScheme.nip04);
      expect(nip44.scheme, EncryptionScheme.nip44);
      expect(nip44.plaintext, 'hello');
      expect(nip44.recipientPubkey, 'b');
    });

    test('a decryption names its scheme and sender', () {
      final nip04 = PendingDecryptRequest.nip04(
        id: 'req-004',
        createdAt: createdAt,
        signerPubkey: 'a',
        ciphertext: 'encrypted',
        senderPubkey: 'b',
      );
      final nip44 = PendingDecryptRequest.nip44(
        id: 'req-005',
        createdAt: createdAt,
        signerPubkey: 'a',
        ciphertext: 'encrypted',
        senderPubkey: 'b',
      );

      expect(nip04.scheme, EncryptionScheme.nip04);
      expect(nip44.scheme, EncryptionScheme.nip44);
      expect(nip44.ciphertext, 'encrypted');
      expect(nip44.senderPubkey, 'b');
    });

    test('toString names the request and what it waits for', () {
      final sign = PendingSignRequest(
        id: 'req-006',
        createdAt: createdAt,
        signerPubkey: 'a',
        event: Nip01Event(pubkey: 'a', kind: 1, content: ''),
      );
      final decrypt = PendingDecryptRequest.nip44(
        id: 'req-007',
        createdAt: createdAt,
        signerPubkey: 'a',
        ciphertext: 'encrypted',
        senderPubkey: 'b',
      );

      expect(sign.toString(), startsWith('PendingSignRequest(id: req-006'));
      expect(sign.toString(), contains('kind: 1'));
      expect(
        decrypt.toString(),
        startsWith('PendingDecryptRequest(id: req-007, nip44'),
      );
    });
  });
}
