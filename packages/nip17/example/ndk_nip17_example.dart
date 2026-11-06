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

  final dms = Dms(
    accounts: ndk.accounts,
    giftWrap: ndk.giftWrap,
    eventVerifier: ndk.config.eventVerifier,
    getDmRelays: ndk.userRelayLists.getDmRelays,
    query:
        (
          filter, {
          required relays,
          required auth,
          required cacheRead,
          required timeout,
        }) => ndk.requests
            .query(
              filter: filter,
              explicitRelays: relays,
              auth: auth,
              cacheRead: cacheRead,
              timeout: timeout,
            )
            .future,
    publish: (event, {relays}) => ndk.broadcast
        .broadcast(nostrEvent: event, specificRelays: relays)
        .broadcastDoneFuture,
    loadCachedGiftWraps: (pubKey) => ndk.config.cache.loadEvents(
      kinds: [GiftWrap.kGiftWrapEventkind],
      tags: {
        'p': [pubKey],
      },
    ),
  );
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
