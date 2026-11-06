import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_nip59/ndk_nip59.dart';
import 'package:ndk_signer/ndk_signer.dart';

Future<void> main() async {
  final alice = Bip340.generatePrivateKey();
  final bob = Bip340.generatePrivateKey();
  EventSigner signerOf(KeyPair key) =>
      Bip340EventSigner(privateKey: key.privateKey, publicKey: key.publicKey);

  var current = signerOf(alice);
  final giftWrap = GiftWrap(
    signer: () => current,
    eventVerifier: Bip340EventVerifier(),
    eventSignerFactory: const Bip340EventSignerFactory(),
  );

  final rumor = await giftWrap.createRumor(
    content: 'hello bob',
    kind: 14,
    tags: [
      ['p', bob.publicKey],
    ],
  );
  final wrap = await giftWrap.toGiftWrap(
    rumor: rumor,
    recipientPubkey: bob.publicKey,
  );
  print('kind ${wrap.kind} signed by ${wrap.pubKey}');

  current = signerOf(bob);
  final received = await giftWrap.fromGiftWrap(giftWrap: wrap);
  print(received.content);
}
