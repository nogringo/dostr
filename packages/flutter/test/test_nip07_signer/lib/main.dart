import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

void test() async {
  final nip07Signer = Nip07Signer();
  final bip340Signer = Bip340Signer(
    privateKey:
        'e4bd52924bce6a9c58d2decc7fe91b376d6a6513fc615aabc9e071f2b436b127',
    publicKey:
        '953f12b4f6966a289fde9adfc511e00a66cfa4cb9d69551dee51f3f387e8e277',
  );

  try {
    print('can sign passed : ${testCanSign(nip07Signer)}');
    print('pubkey passed : ${await testGetPubKey(nip07Signer)}');
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

Future<bool> testGetPubKey(Nip07Signer nip07Signer) async {
  final pubkey = await nip07Signer.getPublicKeyAsync();
  print(pubkey);
  return pubkey.isNotEmpty;
}

bool testCanSign(Nip07Signer nip07Signer) {
  return nip07Signer.canSign();
}

Future<bool> testSendEncrypted(
  Nip07Signer nip07Signer,
  Bip340Signer bip340Signer,
) async {
  const message = 'Hello';

  final encryptedMessage = await nip07Signer.encrypt(
    message,
    bip340Signer.publicKey,
  );

  final decryptedMessage = await bip340Signer.decrypt(
    encryptedMessage!,
    await nip07Signer.getPublicKeyAsync(),
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
    recipientPubKey: bip340Signer.publicKey,
  );

  final decryptedMessage = await bip340Signer.decryptNip44(
    ciphertext: encryptedMessage!,
    senderPubKey: await nip07Signer.getPublicKeyAsync(),
  );

  return message == decryptedMessage;
}

Future<bool> testReceiveEncrypted(
  Nip07Signer nip07Signer,
  Bip340Signer bip340Signer,
) async {
  const message = 'Hello';

  final encryptedMessage = await bip340Signer.encrypt(
    message,
    await nip07Signer.getPublicKeyAsync(),
  );

  final decryptedMessage = await nip07Signer.decrypt(
    encryptedMessage!,
    bip340Signer.publicKey,
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
    recipientPubKey: await nip07Signer.getPublicKeyAsync(),
  );

  final decryptedMessage = await nip07Signer.decryptNip44(
    ciphertext: encryptedMessage!,
    senderPubKey: bip340Signer.publicKey,
  );

  return message == decryptedMessage;
}

Future<bool> testSign(Nip07Signer nip07Signer) async {
  final pubKey = await nip07Signer.getPublicKeyAsync();
  final event = Nip01Event(
    pubKey: pubKey,
    kind: 1,
    tags: [
      ['p', pubKey],
      ['lalala', 'pubKey'],
    ],
    content: 'GM',
  );

  final signedEvent = await nip07Signer.sign(event);

  return await Bip340EventVerifier().verify(signedEvent) &&
      signedEvent.kind == 1 &&
      signedEvent.pubKey == pubKey &&
      signedEvent.content == 'GM';
}
