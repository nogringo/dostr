import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

/// Runs the contract every [EventVerifier] must meet against one
/// implementation: accept what was signed, reject anything changed after
/// signing or not encoded as NIP-01 lowercase hex, and answer `false` rather
/// than throw on malformed input.
///
/// [createSigner] must return a signer with a fresh key on each call, using
/// the signature scheme the verifier checks. [externalEvents], in their JSON
/// form, are events another implementation signed, such as
/// [bip340ExternalEvents]: each must verify.
///
/// ```dart
/// runEventVerifierTestSuite(
///   name: 'Bip340EventVerifier',
///   createVerifier: Bip340EventVerifier.new,
///   createSigner: const Bip340EventSignerFactory().createWithNewKeyPair,
///   externalEvents: bip340ExternalEvents,
/// );
/// ```
void runEventVerifierTestSuite({
  required String name,
  required EventVerifier Function() createVerifier,
  required EventSigner Function() createSigner,
  Iterable<Map<String, Object>> externalEvents = const [],
}) {
  group(name, () {
    late EventVerifier verifier;
    late EventSigner signer;

    setUp(() {
      verifier = createVerifier();
      signer = createSigner();
    });

    tearDown(() => signer.dispose());

    Future<Nip01Event> sign({
      String? pubKey,
      int kind = 1,
      int createdAt = 1726215220,
      List<List<String>> tags = const [],
      String content = 'hello',
    }) => signer.sign(
      Nip01Event(
        pubKey: pubKey ?? signer.getPublicKey(),
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
      ),
    );

    // A signer sharing a serialization bug with its verifier still agrees
    // with it: only events signed elsewhere catch that.
    if (externalEvents.isNotEmpty) {
      group('accepts an event signed by another implementation', () {
        for (final json in externalEvents) {
          final event = Nip01Event.fromJson(json);
          test(event.id, () async {
            expect(await verifier.verify(event), isTrue);
          });
        }
      });
    }

    group('accepts a signed event', () {
      final shapes = <String, Future<Nip01Event> Function()>{
        'with plain content': () => sign(),
        'with empty content and no tags': () => sign(content: ''),
        'with a tag that has no items': () => sign(tags: [<String>[]]),
        'with an empty tag value': () => sign(
          tags: [
            ['t', ''],
          ],
        ),
        'with quotes and backslashes': () => sign(
          tags: [
            ['t', r'"\'],
          ],
          content: r'say "hi" \o/',
        ),
        'with unicode': () => sign(
          tags: [
            ['t', 'Привет мир'],
          ],
          content: '你好世界 🌍',
        ),
        'of kind 0': () => sign(kind: 0),
        'of kind 65535': () => sign(kind: 65535),
        'created at 0': () => sign(createdAt: 0),
        'with 200 tags of 1 KiB and 64 KiB of content': () => sign(
          tags: List.generate(200, (index) => ['x', '$index-${'a' * 1024}']),
          content: 'b' * (64 * 1024),
        ),
        for (var code = 0; code < 0x20; code++) ...{
          'with control character $code in its content': () =>
              sign(content: 'before${String.fromCharCode(code)}after'),
          'with control character $code in a tag': () => sign(
            tags: [
              ['t', 'before${String.fromCharCode(code)}after'],
            ],
          ),
        },
      };

      for (final MapEntry(key: shape, value: signEvent) in shapes.entries) {
        test(shape, () async {
          expect(await verifier.verify(await signEvent()), isTrue);
        });
      }
    });

    group('rejects an event changed after signing', () {
      late Nip01Event event;

      setUp(() async {
        event = await sign(
          tags: [
            ['t', 'nostr'],
            ['r', 'wss://relay.example.com'],
          ],
        );
      });

      // copyWith recomputes the id unless it is given.
      final changes = <String, Nip01Event Function(Nip01Event)>{
        'with its content replaced': (e) =>
            e.copyWith(id: e.id, content: 'bye'),
        'with a NUL suffix in its content': (e) => e.copyWith(
          id: e.id,
          content: '${e.content}\u0000 send me your nsec',
        ),
        'with a tag value replaced': (e) => e.copyWith(
          id: e.id,
          tags: [
            ['t', 'bitcoin'],
            e.tags[1],
          ],
        ),
        'with a NUL suffix in a tag value': (e) => e.copyWith(
          id: e.id,
          tags: [
            ['t', 'nostr\u0000evil'],
            e.tags[1],
          ],
        ),
        'with an item added to a tag': (e) => e.copyWith(
          id: e.id,
          tags: [
            ['t', 'nostr', 'evil'],
            e.tags[1],
          ],
        ),
        'with a tag added': (e) => e.copyWith(
          id: e.id,
          tags: [
            ...e.tags,
            ['t', 'evil'],
          ],
        ),
        'with a tag removed': (e) => e.copyWith(id: e.id, tags: [e.tags[0]]),
        'with its kind shifted by 1': (e) =>
            e.copyWith(id: e.id, kind: e.kind + 1),
        'with its kind shifted by 65536': (e) =>
            e.copyWith(id: e.id, kind: e.kind + 65536),
        'with its kind shifted by 2^32': (e) =>
            e.copyWith(id: e.id, kind: e.kind + 4294967296),
        'with its created_at shifted by 1': (e) =>
            e.copyWith(id: e.id, createdAt: e.createdAt + 1),
        'with its created_at shifted by 2^32': (e) =>
            e.copyWith(id: e.id, createdAt: e.createdAt + 4294967296),
        'with one bit of its sig flipped': (e) =>
            e.copyWith(sig: _flipLastHexDigit(e.sig!)),
      };

      for (final MapEntry(key: change, value: apply) in changes.entries) {
        test(change, () async {
          expect(await verifier.verify(apply(event)), isFalse);
        });
      }

      test('with the pubkey of another key', () async {
        final other = createSigner();
        addTearDown(other.dispose);
        final forged = event.copyWith(
          id: event.id,
          pubKey: other.getPublicKey(),
        );

        expect(await verifier.verify(forged), isFalse);
      });
    });

    group('rejects an event whose', () {
      late Nip01Event event;

      setUp(() async {
        event = await sign();
      });

      test('sig is missing', () async {
        final unsigned = Nip01Event(
          id: event.id,
          pubKey: event.pubKey,
          createdAt: event.createdAt,
          kind: event.kind,
          tags: event.tags,
          content: event.content,
        );

        expect(await verifier.verify(unsigned), isFalse);
      });

      final malformations = <String, String Function(String)>{
        'is empty': (_) => '',
        'is cut in half': (hex) => hex.substring(0, hex.length ~/ 2),
        'is one byte short': (hex) => hex.substring(0, hex.length - 2),
        'is one byte long': (hex) => '${hex}00',
        'has an odd length': (hex) => hex.substring(0, hex.length - 1),
        'has a non-hex character': _putNonHexInNonZeroByte,
      };

      for (final MapEntry(key: malformation, value: malform)
          in malformations.entries) {
        test('sig $malformation', () async {
          final malformed = event.copyWith(sig: malform(event.sig!));

          expect(await verifier.verify(malformed), isFalse);
        });

        test('id $malformation', () async {
          final malformed = event.copyWith(
            id: malform(event.id),
            sig: event.sig,
          );

          expect(await verifier.verify(malformed), isFalse);
        });

        // The id is recomputed, so the verifier gets past the id check and
        // has to decode the malformed pubkey itself.
        test('pubkey $malformation', () async {
          final malformed = event.copyWith(
            pubKey: malform(event.pubKey),
            sig: event.sig,
          );

          expect(await verifier.verify(malformed), isFalse);
        });
      }

      test('sig is uppercase', () async {
        final malformed = event.copyWith(sig: event.sig!.toUpperCase());

        expect(await verifier.verify(malformed), isFalse);
      });

      test('id is uppercase', () async {
        final malformed = event.copyWith(
          id: event.id.toUpperCase(),
          sig: event.sig,
        );

        expect(await verifier.verify(malformed), isFalse);
      });

      // Lenient decoders such as int.parse and JS parseInt read "+X" as the
      // byte 0X. Re-signing other content finds a sig with such a byte.
      test('sig has a + sign', () async {
        var signed = event;
        var index = _zeroHighNibbleIndex(signed.sig!);
        for (var attempt = 1; index < 0; attempt++) {
          signed = await sign(content: 'hello $attempt');
          index = _zeroHighNibbleIndex(signed.sig!);
        }
        final malformed = signed.copyWith(
          sig: signed.sig!.replaceRange(index, index + 1, '+'),
        );

        expect(await verifier.verify(malformed), isFalse);
      });

      test('pubkey is uppercase, signed as such', () async {
        final uppercase = signer.getPublicKey().toUpperCase();
        final signed = await sign(pubKey: uppercase);
        if (signed.pubKey != uppercase) {
          markTestSkipped('the signer replaces the pubkey of what it signs');
          return;
        }

        expect(await verifier.verify(signed), isFalse);
      });
    });
  });
}

int _zeroHighNibbleIndex(String hex) {
  for (var index = 0; index < hex.length; index += 2) {
    if (hex[index] == '0') return index;
  }
  return -1;
}

String _flipLastHexDigit(String hex) {
  final last = int.parse(hex[hex.length - 1], radix: 16) ^ 1;
  return '${hex.substring(0, hex.length - 1)}${last.toRadixString(16)}';
}

// Lenient decoders such as JS parseInt read "zX" as 0: on a byte that is
// already 0 the value would not change, and a lenient verifier would pass.
String _putNonHexInNonZeroByte(String hex) {
  var index = 0;
  while (index + 2 < hex.length && hex.startsWith('00', index)) {
    index += 2;
  }
  return hex.replaceRange(index, index + 1, 'z');
}
