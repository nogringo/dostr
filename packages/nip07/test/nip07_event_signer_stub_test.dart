@TestOn('vm')
library;

import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_nip07/ndk_nip07.dart';
import 'package:test/test.dart';

void main() {
  group('Nip07EventSigner outside the browser', () {
    late Nip07EventSigner signer;

    setUp(() => signer = Nip07EventSigner(cachedPublicKey: 'pubkey'));
    tearDown(() => signer.dispose());

    test('cannot sign', () {
      expect(signer.canSign(), isFalse);
      expect(signer.requiresInteractiveSigning, isTrue);
      expect(signer.cachedPublicKey, 'pubkey');
    });

    test('throws UnsupportedError for every request', () {
      final event = Nip01Event(
        pubKey: 'pubkey',
        kind: 1,
        tags: [],
        content: '',
      );

      expect(() => signer.getPublicKey(), throwsUnsupportedError);
      expect(signer.getPublicKeyAsync, throwsUnsupportedError);
      expect(signer.sign(event), throwsUnsupportedError);
      expect(signer.encrypt('msg', 'pubkey'), throwsUnsupportedError);
      expect(signer.decrypt('msg', 'pubkey'), throwsUnsupportedError);
      expect(
        signer.encryptNip44(plaintext: 'msg', recipientPubKey: 'pubkey'),
        throwsUnsupportedError,
      );
      expect(
        signer.decryptNip44(ciphertext: 'msg', senderPubKey: 'pubkey'),
        throwsUnsupportedError,
      );
    });

    test('has no pending requests', () {
      expect(signer.pendingRequests, isEmpty);
      expect(signer.cancelRequest('id'), isFalse);
    });
  });
}
