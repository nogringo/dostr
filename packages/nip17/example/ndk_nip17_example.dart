import 'dart:convert';
import 'dart:typed_data';

import 'package:ndk/ndk.dart';
import 'package:ndk_nip17/ndk_nip17.dart';

Future<void> main() async {
  final ndk = Ndk.emptyBootstrapRelaysConfig();
  final alice = Bip340.generatePrivateKey();
  ndk.accounts.loginPrivateKey(
    pubkey: alice.publicKey,
    privkey: alice.privateKey!,
  );

  final dms = Dms(ndk);
  final conversations = await dms.loadConversationsSnapshot();
  print('${conversations.length} cached conversations');

  final encrypted = await Nip17FileCrypto.encrypt(
    Uint8List.fromList(utf8.encode('hello')),
  );
  final metadata = Nip17FileMetadata.fromEncryptedFile(
    url: Uri.parse('https://blossom.example.com/${encrypted.encryptedSha256}'),
    mimeType: 'text/plain',
    encryptedFile: encrypted,
  );
  final plaintext = await Nip17FileCrypto.decrypt(
    ciphertext: encrypted.ciphertext,
    metadata: metadata,
  );
  print(utf8.decode(plaintext));

  await ndk.destroy();
}
