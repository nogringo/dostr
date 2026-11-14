import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  const signerFactory = DostrEventSignerFactory();
  final verifier = DostrEventVerifier();

  Future<Nip01Event> signNote(EventSigner signer) => signer.sign(
    Nip01Event(
      pubKey: alicePubkey,
      kind: 1,
      tags: [
        ['t', 'nostr'],
      ],
      content: 'hi',
      createdAt: 1700000000,
    ),
  );

  test('DostrEventSignerFactory derives the BIP-340 public key', () {
    expect(signerFactory.derivePublicKey(alicePrivateKey), alicePubkey);

    final (privateKey, publicKey) = signerFactory.generateKeyPair();
    expect(Bip340.getPublicKey(privateKey), publicKey);
  });

  test('DostrEventVerifier accepts what either signer signed', () async {
    final platformSigned = await signNote(
      signerFactory.create(privateKey: alicePrivateKey),
    );
    final bip340Signed = await signNote(
      Bip340EventSigner(privateKey: alicePrivateKey, publicKey: alicePubkey),
    );

    expect(await verifier.verify(platformSigned), isTrue);
    expect(await verifier.verify(bip340Signed), isTrue);
    expect(await Bip340EventVerifier().verify(platformSigned), isTrue);
  });

  test('DostrEventVerifier rejects a changed or unsigned event', () async {
    final signed = await signNote(
      signerFactory.create(privateKey: alicePrivateKey),
    );
    final otherSigned = await signNote(
      signerFactory.create(privateKey: 'ab' * 32),
    );

    expect(
      await verifier.verify(
        signed.copyWith(content: 'bye', id: signed.id, sig: signed.sig),
      ),
      isFalse,
    );
    expect(
      await verifier.verify(signed.copyWith(sig: otherSigned.sig)),
      isFalse,
    );
    expect(await verifier.verify(signed.copyWith(content: 'bye')), isFalse);
  });
}
