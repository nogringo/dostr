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

    String mutateHex(String value) {
      final first = value[0].toLowerCase();
      final replacement = first == 'a' ? 'b' : 'a';
      return '$replacement${value.substring(1)}';
    }

    setUp(() {
      verifier = RustEventVerifier();
      keyPair = Bip340.generatePrivateKey();
    });

    Nip01Event signed(Nip01Event event) =>
        event.copyWith(sig: Bip340.sign(event.id, keyPair.privateKey!));

    test('verifies valid event', () async {
      final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final event = signed(
        Nip01Event(
          pubKey: keyPair.publicKey,
          createdAt: createdAt,
          kind: 1,
          tags: [],
          content: 'hello world',
        ),
      );

      final result = await verifier.verify(event);
      expect(result, isTrue);
    });

    test('rejects event with invalid signature', () async {
      final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final event = signed(
        Nip01Event(
          pubKey: keyPair.publicKey,
          createdAt: createdAt,
          kind: 1,
          tags: [],
          content: 'hello world',
        ),
      );

      final result = await verifier.verify(
        event.copyWith(sig: mutateHex(event.sig!)),
      );
      expect(result, isFalse);
    });

    test('rejects event with wrong id', () async {
      final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final event = signed(
        Nip01Event(
          pubKey: keyPair.publicKey,
          createdAt: createdAt,
          kind: 1,
          tags: [],
          content: 'hello world',
        ),
      );

      final result = await verifier.verify(
        event.copyWith(id: 'a' * 64, sig: event.sig),
      );
      expect(result, isFalse);
    });

    test('verifies event with tags', () async {
      final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final tags = [
        ['e', 'abc123def456789012345678901234567890123456789012345678901234'],
        ['p', keyPair.publicKey],
      ];
      final content = 'hello with tags';

      final event = signed(
        Nip01Event(
          pubKey: keyPair.publicKey,
          createdAt: createdAt,
          kind: 1,
          tags: tags,
          content: content,
        ),
      );

      final result = await verifier.verify(event);
      expect(result, isTrue);
    });

    test('verifies event with empty content', () async {
      final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final content = '';

      final event = signed(
        Nip01Event(
          pubKey: keyPair.publicKey,
          createdAt: createdAt,
          kind: 1,
          tags: [],
          content: content,
        ),
      );

      final result = await verifier.verify(event);
      expect(result, isTrue);
    });

    test('verifies event with unicode content', () async {
      final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final content = '你好世界 🌍 Привет мир';

      final event = signed(
        Nip01Event(
          pubKey: keyPair.publicKey,
          createdAt: createdAt,
          kind: 1,
          tags: [],
          content: content,
        ),
      );

      final result = await verifier.verify(event);
      expect(result, isTrue);
    });

    // NUL cannot cross the current null-terminated string FFI; Rust hash tests
    // cover its serialization directly along with all other control characters.
    for (var code = 1; code < 0x20; code++) {
      for (final inTag in [false, true]) {
        test(
          'verifies control character $code in ${inTag ? 'tag' : 'content'}',
          () async {
            final value = 'before${String.fromCharCode(code)}after';
            final tags = inTag
                ? [
                    ['t', value],
                  ]
                : <List<String>>[];
            final content = inTag ? '' : value;
            final event = signed(
              Nip01Event(
                pubKey: keyPair.publicKey,
                createdAt: 1726215220,
                kind: 1,
                tags: tags,
                content: content,
              ),
            );

            expect(await verifier.verify(event), isTrue);
          },
        );
      }
    }

    test('rejects malformed fixed-size signature fields', () async {
      final event = Nip01Event(
        id: 'z' * 64,
        pubKey: keyPair.publicKey,
        kind: 1,
        tags: const [],
        content: '',
        sig: '0' * 128,
      );

      expect(await verifier.verify(event), isFalse);
    });

    test('rejects malformed packed FFI inputs for the combined id/signature '
        'check', () {
      const packedLength = 64 + 64 + 128;
      const oversizedLength = packedLength + 10;
      final truncatedPacked = calloc<Uint8>(packedLength - 10);
      final packed = malloc<Uint8>(oversizedLength);
      final content = ''.toNativeUtf8();

      try {
        packed.asTypedList(packedLength).fillRange(0, packedLength, 0x7a);

        expect(
          rust_lib.verifyNostrEventPackedNative(
            truncatedPacked,
            packedLength - 10,
            0,
            1,
            nullptr,
            nullptr,
            0,
            content,
          ),
          0,
        );
        expect(
          rust_lib.verifyNostrEventPackedNative(
            packed,
            oversizedLength,
            0,
            1,
            nullptr,
            nullptr,
            0,
            content,
          ),
          0,
        );
        expect(
          rust_lib.verifyNostrEventPackedNative(
            Pointer.fromAddress(0),
            packedLength,
            0,
            1,
            nullptr,
            nullptr,
            0,
            content,
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
            nullptr,
            nullptr,
            0,
            content,
          ),
          0,
        );
      } finally {
        calloc.free(truncatedPacked);
        malloc.free(packed);
        malloc.free(content);
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
