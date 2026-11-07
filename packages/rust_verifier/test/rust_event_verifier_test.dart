import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_rust_verifier/ndk_rust_verifier.dart';
import 'package:ndk_rust_verifier/src/rust_lib.dart' as rust_lib;
import 'package:test/test.dart';

void main() {
  group('RustEventVerifier', () {
    late RustEventVerifier verifier;
    late KeyPair keyPair;

    setUp(() {
      verifier = RustEventVerifier();
      keyPair = Bip340.generatePrivateKey();
    });

    Nip01Event signed(Nip01Event event) =>
        event.copyWith(sig: Bip340.sign(event.id, keyPair.privateKey!));

    test('rejects malformed packed FFI inputs for the combined id/signature '
        'check', () {
      const packedLength = 64 + 64 + 128;
      const oversizedLength = packedLength + 10;
      final truncatedPacked = calloc<Uint8>(packedLength - 10);
      final packed = malloc<Uint8>(oversizedLength);
      final text = calloc<Uint8>(1);

      try {
        packed.asTypedList(packedLength).fillRange(0, packedLength, 0x7a);

        expect(
          rust_lib.verifyNostrEventPackedNative(
            truncatedPacked,
            packedLength - 10,
            0,
            1,
            text,
            0,
            0,
            nullptr,
            nullptr,
            0,
          ),
          0,
        );
        expect(
          rust_lib.verifyNostrEventPackedNative(
            packed,
            oversizedLength,
            0,
            1,
            text,
            0,
            0,
            nullptr,
            nullptr,
            0,
          ),
          0,
        );
        expect(
          rust_lib.verifyNostrEventPackedNative(
            Pointer.fromAddress(0),
            packedLength,
            0,
            1,
            text,
            0,
            0,
            nullptr,
            nullptr,
            0,
          ),
          0,
        );
        // Well-formed but non-matching id/pubkey/signature: id hash won't match.
        expect(
          rust_lib.verifyNostrEventPackedNative(
            packed,
            packedLength,
            0,
            1,
            text,
            0,
            0,
            nullptr,
            nullptr,
            0,
          ),
          0,
        );
      } finally {
        calloc.free(truncatedPacked);
        malloc.free(packed);
        calloc.free(text);
      }
    });

    test(
      'accepts event whose declared proof-of-work target is not met',
      () async {
        final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final tags = [
          ['nonce', '1', '255'],
        ];
        final event = signed(
          Nip01Event(
            pubKey: keyPair.publicKey,
            createdAt: createdAt,
            kind: 1,
            tags: tags,
            content: 'pow test',
          ),
        );

        expect(await verifier.verify(event), isTrue);
      },
    );

    test('repeatedly verifies an event with many large tags', () async {
      final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final tags = List.generate(200, (index) => ['x', '$index-${'a' * 1024}']);
      final event = signed(
        Nip01Event(
          pubKey: keyPair.publicKey,
          createdAt: createdAt,
          kind: 1,
          tags: tags,
          content: 'large tagged event',
        ),
      );

      for (var iteration = 0; iteration < 100; iteration++) {
        expect(await verifier.verify(event), isTrue);
      }
    });
  });
}
