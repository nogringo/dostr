@TestOn('vm')
library;

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip07/dostr_nip07.dart';
import 'package:test/test.dart';

import 'fake_extension.dart';

void main() {
  group('Nip07Signer outside the browser', () {
    late Nip07Signer signer;

    setUp(() => signer = Nip07Signer(publicKey: extensionPubkey));
    tearDown(() => signer.dispose());

    test('cannot sign', () {
      expect(Nip07Signer.isAvailable, isFalse);
      expect(signer.canSign, isFalse);
    });

    test('waitForExtension completes with false at once', () async {
      expect(
        await Nip07Signer.waitForExtension(timeout: const Duration(minutes: 1)),
        isFalse,
      );
    });

    test('gives the public key it was given, as in the browser', () {
      expect(signer.publicKey, extensionPubkey);
    });

    test('throws UnsupportedError for every request', () {
      final event = Nip01Event(
        pubkey: extensionPubkey,
        kind: 1,
        tags: [],
        content: '',
      );

      expect(Nip07Signer.connect(), throwsUnsupportedError);
      expect(signer.sign(event), throwsUnsupportedError);
      expect(
        signer.encryptNip04(plaintext: 'msg', recipientPubkey: extensionPubkey),
        throwsUnsupportedError,
      );
      expect(
        signer.decryptNip04(ciphertext: 'msg', senderPubkey: extensionPubkey),
        throwsUnsupportedError,
      );
      expect(
        signer.encryptNip44(plaintext: 'msg', recipientPubkey: extensionPubkey),
        throwsUnsupportedError,
      );
      expect(
        signer.decryptNip44(ciphertext: 'msg', senderPubkey: extensionPubkey),
        throwsUnsupportedError,
      );
    });

    test('has no pending requests', () {
      expect(signer.pendingRequests, isEmpty);
      expect(signer.cancelRequest('id'), isFalse);
    });
  });
}
