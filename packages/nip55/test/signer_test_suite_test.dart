import 'dart:convert';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip55/dostr_nip55.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';

/// A signer app that holds the key of [signer].
class _Bip340SignerApp extends Nip55SignerApp {
  _Bip340SignerApp(this.signer);

  final Bip340Signer signer;

  /// A signer app answers a request it cannot carry out with no result.
  Future<Map<dynamic, dynamic>> _answer(Future<String> Function() run) async {
    try {
      return {'signature': await run()};
    } on SignerRequestException {
      return {};
    }
  }

  @override
  Future<Map<dynamic, dynamic>> signEvent({
    required String currentUser,
    required String eventJson,
    String? id,
  }) async {
    final signed = await signer.sign(
      Nip01Event.fromJson(jsonDecode(eventJson)),
    );
    return {'signature': signed.sig, 'event': signed.toJsonString()};
  }

  @override
  Future<Map<dynamic, dynamic>> nip44Encrypt({
    required String plaintext,
    required String currentUser,
    required String pubkey,
    String? id,
  }) => _answer(
    () => signer.encryptNip44(plaintext: plaintext, recipientPubkey: pubkey),
  );

  @override
  Future<Map<dynamic, dynamic>> nip44Decrypt({
    required String ciphertext,
    required String currentUser,
    required String pubkey,
    String? id,
  }) => _answer(
    () => signer.decryptNip44(ciphertext: ciphertext, senderPubkey: pubkey),
  );

  @override
  Future<Map<dynamic, dynamic>> nip04Encrypt({
    required String plaintext,
    required String currentUser,
    required String pubkey,
    String? id,
  }) => _answer(
    () => signer.encryptNip04(plaintext: plaintext, recipientPubkey: pubkey),
  );

  @override
  Future<Map<dynamic, dynamic>> nip04Decrypt({
    required String ciphertext,
    required String currentUser,
    required String pubkey,
    String? id,
  }) => _answer(
    () => signer.decryptNip04(ciphertext: ciphertext, senderPubkey: pubkey),
  );
}

void main() {
  const signerFactory = Bip340SignerFactory();

  runSignerTestSuite(
    name: 'Nip55Signer',
    createSigner: () {
      final keyPair = Bip340.generatePrivateKey();
      return Nip55Signer(
        publicKey: keyPair.publicKey,
        signerApp: _Bip340SignerApp(
          Bip340Signer(
            privateKey: keyPair.privateKey,
            publicKey: keyPair.publicKey,
          ),
        ),
      );
    },
    createPeer: signerFactory.createWithNewKeyPair,
    verifier: Bip340EventVerifier(),
    interactive: true,
  );
}
