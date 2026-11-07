import 'dart:convert';

import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

void main() {
  test("complete metadata workflow preserves all data", () async {
    final keypair = Bip340.generatePrivateKey();

    final signer = Bip340EventSigner(
      privateKey: keypair.privateKey,
      publicKey: keypair.publicKey,
    );

    final cache = MemCacheManager();

    final metadataEvent = Nip01Event(
      pubKey: keypair.publicKey,
      kind: 0,
      tags: [
        ["i", "badge"],
      ],
      content: '{"name":"Alice","badges":["A","B"]}',
    );

    final signedMetadataEvent = await signer.sign(metadataEvent);

    await cache.saveEvent(signedMetadataEvent);

    final savedMetadata = await cache.loadMetadata(keypair.publicKey);

    expect(savedMetadata, isNotNull);

    savedMetadata!.tags.add(["i", "test"]);

    final newMetadataEvent = savedMetadata.toEvent();

    final newMetadataSignedEvent = await signer.sign(newMetadataEvent);

    expect(newMetadataSignedEvent.tags.length, equals(2));
    expect(
      List.from(jsonDecode(newMetadataSignedEvent.content)["badges"]).length,
      equals(2),
    );
  });
}
