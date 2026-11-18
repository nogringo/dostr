import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

void test() async {
  final bip340Signer = Bip340Signer(
    'e4bd52924bce6a9c58d2decc7fe91b376d6a6513fc615aabc9e071f2b436b127',
  );

  try {
    print('can sign passed : ${Nip07Signer.isAvailable}');
    final nip07Signer = await Nip07Signer.connect();
    print('pubkey passed : ${nip07Signer.publicKey.isNotEmpty}');
    print(
      'send encrypted passed : ${await testSendEncrypted(nip07Signer, bip340Signer)}',
    );
    print(
      'send encrypted nip44 passed : ${await testSendEncryptedNip44(nip07Signer, bip340Signer)}',
    );
    print(
      'receive encrypted passed : ${await testReceiveEncrypted(nip07Signer, bip340Signer)}',
    );
    print(
      'receive encrypted nip44 passed : ${await testReceiveEncryptedNip44(nip07Signer, bip340Signer)}',
    );
    print('sign passed : ${await testSign(nip07Signer)}');
  } catch (_) {
    print('Error');
  }
}

Future<bool> testSendEncrypted(
  Nip07Signer nip07Signer,
  Bip340Signer bip340Signer,
) async {
  const message = 'Hello';

  final encryptedMessage = await nip07Signer.encryptNip04(
    plaintext: message,
    recipientPubkey: bip340Signer.publicKey,
  );

  final decryptedMessage = await bip340Signer.decryptNip04(
    ciphertext: encryptedMessage,
    senderPubkey: nip07Signer.publicKey,
  );

  return message == decryptedMessage;
}

Future<bool> testSendEncryptedNip44(
  Nip07Signer nip07Signer,
  Bip340Signer bip340Signer,
) async {
  const message = 'Hello';

  final encryptedMessage = await nip07Signer.encryptNip44(
    plaintext: message,
    recipientPubkey: bip340Signer.publicKey,
  );

  final decryptedMessage = await bip340Signer.decryptNip44(
    ciphertext: encryptedMessage,
    senderPubkey: nip07Signer.publicKey,
  );

  return message == decryptedMessage;
}

Future<bool> testReceiveEncrypted(
  Nip07Signer nip07Signer,
  Bip340Signer bip340Signer,
) async {
  const message = 'Hello';

  final encryptedMessage = await bip340Signer.encryptNip04(
    plaintext: message,
    recipientPubkey: nip07Signer.publicKey,
  );

  final decryptedMessage = await nip07Signer.decryptNip04(
    ciphertext: encryptedMessage,
    senderPubkey: bip340Signer.publicKey,
  );

  return message == decryptedMessage;
}

Future<bool> testReceiveEncryptedNip44(
  Nip07Signer nip07Signer,
  Bip340Signer bip340Signer,
) async {
  const message = 'Hello';

  final encryptedMessage = await bip340Signer.encryptNip44(
    plaintext: message,
    recipientPubkey: nip07Signer.publicKey,
  );

  final decryptedMessage = await nip07Signer.decryptNip44(
    ciphertext: encryptedMessage,
    senderPubkey: bip340Signer.publicKey,
  );

  return message == decryptedMessage;
}

Future<bool> testSign(Nip07Signer nip07Signer) async {
  final pubkey = nip07Signer.publicKey;
  final event = Nip01Event(
    pubkey: pubkey,
    kind: 1,
    tags: [
      ['p', pubkey],
      ['lalala', 'pubKey'],
    ],
    content: 'GM',
  );

  final signedEvent = await nip07Signer.sign(event);

  return await Bip340EventVerifier().verify(signedEvent) &&
      signedEvent.kind == 1 &&
      signedEvent.pubkey == pubkey &&
      signedEvent.content == 'GM';
}
