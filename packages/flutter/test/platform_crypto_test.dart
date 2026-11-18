import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  const signerFactory = DostrSignerFactory();
  final verifier = DostrEventVerifier();

  Future<Nip01Event> signNote(NostrSigner signer) => signer.sign(
    Nip01Event(
      pubkey: signer.publicKey,
      kind: 1,
      tags: [
        ['t', 'nostr'],
      ],
      content: 'hi',
      createdAt: 1700000000,
    ),
  );

  test('DostrSignerFactory derives the BIP-340 public key', () {
    expect(signerFactory.create(alicePrivateKey).publicKey, alicePubkey);

    final (privateKey, publicKey) = signerFactory.generateKeyPair();
    expect(Bip340.getPublicKey(privateKey), publicKey);
  });

  test('DostrEventVerifier accepts what either signer signed', () async {
    final platformSigned = await signNote(
      signerFactory.create(alicePrivateKey),
    );
    final bip340Signed = await signNote(Bip340Signer(alicePrivateKey));

    expect(await verifier.verify(platformSigned), isTrue);
    expect(await verifier.verify(bip340Signed), isTrue);
    expect(await Bip340EventVerifier().verify(platformSigned), isTrue);
  });

  test('DostrEventVerifier rejects a changed or unsigned event', () async {
    final signed = await signNote(signerFactory.create(alicePrivateKey));
    final otherSigned = await signNote(signerFactory.create('ab' * 32));

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
