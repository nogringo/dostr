import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

/// Runs the contract every [NostrSigner] must keep against one
/// implementation: sign events of its pubkey and refuse those of another,
/// encrypt for and decrypt from any peer, throw a [SignerRequestException]
/// when a request gets no valid result, and an [Error] when it is misused.
///
/// [createSigner] returns a signer that can sign, and [verifier] checks its
/// signatures. [createPeer] returns a signer with a fresh key on each call,
/// that encrypts for and decrypts from it. [createReadOnlySigner], when given,
/// returns a signer whose [NostrSigner.canSign] is false.
///
/// An [interactive] signer waits for the user: each request is in
/// [NostrSigner.pendingRequests] as soon as the call returns, until it
/// completes or [NostrSigner.cancelRequest] drops it. A local signer lists
/// none.
///
/// ```dart
/// runSignerTestSuite(
///   name: 'Nip46Signer',
///   createSigner: () => Nip46Signer(...),
///   createPeer: const Bip340SignerFactory().createWithNewKeyPair,
///   verifier: Bip340EventVerifier(),
///   interactive: true,
/// );
/// ```
void runSignerTestSuite({
  required String name,
  required FutureOr<NostrSigner> Function() createSigner,
  required FutureOr<NostrSigner> Function() createPeer,
  required EventVerifier verifier,
  FutureOr<NostrSigner> Function()? createReadOnlySigner,
  bool interactive = false,
}) {
  group(name, () {
    late NostrSigner signer;
    late NostrSigner peer;

    setUp(() async {
      signer = await createSigner();
      peer = await createPeer();
    });

    tearDown(() async {
      await signer.dispose();
      await peer.dispose();
    });

    Nip01Event note({
      String? pubkey,
      int kind = 1,
      List<List<String>> tags = const [],
      String content = 'hello',
    }) => Nip01Event(
      pubkey: pubkey ?? signer.publicKey,
      createdAt: 1726215220,
      kind: kind,
      tags: tags,
      content: content,
    );

    test('publicKey is lowercase hex', () {
      expect(signer.publicKey, matches(_lowercaseHex));
    });

    test('canSign is true', () {
      expect(signer.canSign, isTrue);
    });

    group('sign', () {
      final events = <String, Nip01Event Function()>{
        'an event': note,
        'an event with empty content and no tags': () => note(content: ''),
        'an event with quotes, backslashes and unicode': () => note(
          tags: [
            ['t', r'"\', 'Привет мир'],
          ],
          content: r'say "hi" \o/ 你好世界 🌍',
        ),
        'an event with control characters': () => note(
          tags: [
            ['t', 'before\u0000after'],
          ],
          content: 'line\nbreak\ttab\u0001',
        ),
        'an event of kind 0': () =>
            note(kind: 0, content: '{"name":"dostr","about":"été"}'),
      };

      for (final MapEntry(key: shape, value: event) in events.entries) {
        test('signs $shape with its pubkey', () async {
          final signed = await signer.sign(event());

          expect(signed.pubkey, signer.publicKey);
          expect(await verifier.verify(signed), isTrue);
        });
      }

      for (final id in ['00' * 32, 'not an id']) {
        test('signs the payload of an event whose id is "$id"', () async {
          final signed = await signer.sign(note().copyWith(id: id));

          expect(signed.hasValidId, isTrue);
          expect(await verifier.verify(signed), isTrue);
        });
      }

      test('throws an ArgumentError for an event of another pubkey', () async {
        await expectLater(
          () => signer.sign(note(pubkey: peer.publicKey)),
          throwsArgumentError,
        );
        expect(signer.pendingRequests, isEmpty);
      });

      test('throws an ArgumentError for its pubkey in uppercase', () async {
        await expectLater(
          () => signer.sign(note(pubkey: signer.publicKey.toUpperCase())),
          throwsArgumentError,
        );
        expect(signer.pendingRequests, isEmpty);
      });
    });

    for (final encryption in _encryptions) {
      group(encryption.label, () {
        for (final MapEntry(key: label, value: plaintext)
            in _plaintexts.entries) {
          test('encrypts $label for a peer', () async {
            final ciphertext = await encryption.encrypt(
              signer,
              plaintext,
              peer.publicKey,
            );

            expect(
              await encryption.decrypt(peer, ciphertext, signer.publicKey),
              plaintext,
            );
          });

          test('decrypts $label from a peer', () async {
            final ciphertext = await encryption.encrypt(
              peer,
              plaintext,
              signer.publicKey,
            );

            expect(
              await encryption.decrypt(signer, ciphertext, peer.publicKey),
              plaintext,
            );
          });
        }

        test('decrypts concurrent requests, each to its plaintext', () async {
          final plaintexts = [for (var index = 0; index < 5; index++) '$index'];
          final ciphertexts = [
            for (final plaintext in plaintexts)
              await encryption.encrypt(peer, plaintext, signer.publicKey),
          ];

          final decrypted = await Future.wait([
            for (final ciphertext in ciphertexts)
              encryption.decrypt(signer, ciphertext, peer.publicKey),
          ]);

          expect(decrypted, plaintexts);
        });

        test('throws a SignerRequestException for a ciphertext that does not '
            'decrypt', () async {
          await expectLater(
            () => encryption.decrypt(
              signer,
              encryption.invalidCiphertext,
              peer.publicKey,
            ),
            throwsA(isA<SignerRequestException>()),
          );
        });

        if (encryption.authenticated) {
          test('throws a SignerRequestException for a ciphertext of another '
              'sender', () async {
            final stranger = await createPeer();
            addTearDown(stranger.dispose);
            final ciphertext = await encryption.encrypt(
              peer,
              'hello',
              signer.publicKey,
            );

            await expectLater(
              () => encryption.decrypt(signer, ciphertext, stranger.publicKey),
              throwsA(isA<SignerRequestException>()),
            );
          });
        }
      });
    }

    group('pendingRequests', () {
      test('is empty once a request completes', () async {
        await signer.sign(note());

        expect(signer.pendingRequests, isEmpty);
      });

      test('cancelRequest is false for an unknown request', () {
        expect(signer.cancelRequest('unknown'), isFalse);
      });

      if (!interactive) {
        test('lists nothing while a request runs', () async {
          final signing = signer.sign(note());

          expect(signer.pendingRequests, isEmpty);
          await signing;
        });
      } else {
        Matcher waitsOn(String signerPubkey) => isA<PendingSignerRequest>()
            .having((request) => request.id, 'id', isNotEmpty)
            .having(
              (request) => request.signerPubkey,
              'signerPubkey',
              signerPubkey,
            );

        test('lists a signature until it completes', () async {
          final event = note();
          final signing = signer.sign(event);

          expect(signer.pendingRequests, [
            allOf(
              waitsOn(signer.publicKey),
              isA<PendingSignRequest>().having(
                (request) => request.event.id,
                'event.id',
                event.id,
              ),
            ),
          ]);
          await signing;
          expect(signer.pendingRequests, isEmpty);
        });

        for (final encryption in _encryptions) {
          test(
            'lists a ${encryption.label} encryption until it completes',
            () async {
              final encrypting = encryption.encrypt(
                signer,
                'hello',
                peer.publicKey,
              );

              expect(signer.pendingRequests, [
                allOf(
                  waitsOn(signer.publicKey),
                  isA<PendingEncryptRequest>()
                      .having((r) => r.scheme, 'scheme', encryption.scheme)
                      .having((r) => r.plaintext, 'plaintext', 'hello')
                      .having(
                        (r) => r.recipientPubkey,
                        'recipientPubkey',
                        peer.publicKey,
                      ),
                ),
              ]);
              await encrypting;
              expect(signer.pendingRequests, isEmpty);
            },
          );

          test(
            'lists a ${encryption.label} decryption until it completes',
            () async {
              final ciphertext = await encryption.encrypt(
                peer,
                'hello',
                signer.publicKey,
              );
              final decrypting = encryption.decrypt(
                signer,
                ciphertext,
                peer.publicKey,
              );

              expect(signer.pendingRequests, [
                allOf(
                  waitsOn(signer.publicKey),
                  isA<PendingDecryptRequest>()
                      .having((r) => r.scheme, 'scheme', encryption.scheme)
                      .having((r) => r.ciphertext, 'ciphertext', ciphertext)
                      .having(
                        (r) => r.senderPubkey,
                        'senderPubkey',
                        peer.publicKey,
                      ),
                ),
              ]);
              await decrypting;
              expect(signer.pendingRequests, isEmpty);
            },
          );
        }

        test('gives each request its own id', () async {
          final signing = [
            signer.sign(note(content: 'first')),
            signer.sign(note(content: 'second')),
          ];

          expect(
            signer.pendingRequests.map((request) => request.id).toSet(),
            hasLength(2),
          );
          await Future.wait(signing);
        });

        test(
          'pendingRequestsStream emits a request, then an empty list',
          () async {
            final emitted = <List<PendingSignerRequest>>[];
            final subscription = signer.pendingRequestsStream.listen(
              emitted.add,
            );
            addTearDown(subscription.cancel);

            final signing = signer.sign(note());
            final id = signer.pendingRequests.single.id;
            await signing;
            await pumpEventQueue();

            expect(
              emitted,
              contains(
                contains(
                  isA<PendingSignerRequest>().having((r) => r.id, 'id', id),
                ),
              ),
            );
            expect(emitted.last, isEmpty);
          },
        );

        test('cancelRequest fails the request it drops', () async {
          final signing = signer.sign(note());
          final id = signer.pendingRequests.single.id;

          expect(signer.cancelRequest(id), isTrue);
          expect(signer.pendingRequests, isEmpty);
          await expectLater(
            signing,
            throwsA(
              isA<SignerRequestCancelledException>().having(
                (exception) => exception.requestId,
                'requestId',
                id,
              ),
            ),
          );
          expect(signer.cancelRequest(id), isFalse);
        });

        test('cancelRequest is false for a request that completed', () async {
          final signing = signer.sign(note());
          final id = signer.pendingRequests.single.id;
          await signing;

          expect(signer.cancelRequest(id), isFalse);
        });
      }
    });

    if (createReadOnlySigner != null) {
      group('read-only', () {
        late NostrSigner readOnly;

        setUp(() async {
          readOnly = await createReadOnlySigner();
        });

        tearDown(() => readOnly.dispose());

        test('canSign is false', () {
          expect(readOnly.canSign, isFalse);
        });

        test('publicKey is lowercase hex', () {
          expect(readOnly.publicKey, matches(_lowercaseHex));
        });

        final operations = <String, Future<Object?> Function()>{
          'sign': () => readOnly.sign(note(pubkey: readOnly.publicKey)),
          for (final encryption in _encryptions) ...{
            '${encryption.label} encrypt': () =>
                encryption.encrypt(readOnly, 'hello', peer.publicKey),
            '${encryption.label} decrypt': () async => encryption.decrypt(
              readOnly,
              await encryption.encrypt(peer, 'hello', readOnly.publicKey),
              peer.publicKey,
            ),
          },
        };

        for (final MapEntry(key: operation, value: run) in operations.entries) {
          test('$operation throws an Error', () async {
            await expectLater(run, throwsA(isA<Error>()));
            expect(readOnly.pendingRequests, isEmpty);
          });
        }
      });
    }
  });
}

/// Runs the contract every [LocalSignerFactory] must keep against one
/// implementation, then [runSignerTestSuite] against the signers it creates
/// and the read-only ones.
///
/// [verifier] checks the signatures of those signers. [createPeer] defaults to
/// signers of [factory]: pass those of another implementation to check that
/// both encrypt alike.
///
/// ```dart
/// runLocalSignerFactoryTestSuite(
///   name: 'Bip340SignerFactory',
///   factory: const Bip340SignerFactory(),
///   verifier: Bip340EventVerifier(),
/// );
/// ```
void runLocalSignerFactoryTestSuite({
  required String name,
  required LocalSignerFactory factory,
  required EventVerifier verifier,
  FutureOr<NostrSigner> Function()? createPeer,
}) {
  group(name, () {
    test('generateKeyPair makes a new lowercase hex key pair each time', () {
      final (privateKey, publicKey) = factory.generateKeyPair();
      final (otherPrivateKey, otherPublicKey) = factory.generateKeyPair();

      expect(privateKey, matches(_lowercaseHex));
      expect(publicKey, matches(_lowercaseHex));
      expect(otherPrivateKey, isNot(privateKey));
      expect(otherPublicKey, isNot(publicKey));
    });

    test('create derives the public key of the private key', () async {
      final (privateKey, publicKey) = factory.generateKeyPair();
      final signer = factory.create(privateKey);
      addTearDown(signer.dispose);

      expect(signer.publicKey, publicKey);
      expect(signer.canSign, isTrue);
    });

    test('readOnly keeps the public key', () async {
      final (_, publicKey) = factory.generateKeyPair();
      final signer = factory.readOnly(publicKey);
      addTearDown(signer.dispose);

      expect(signer.publicKey, publicKey);
      expect(signer.canSign, isFalse);
    });

    test('createWithNewKeyPair makes a new key each time', () async {
      final signer = factory.createWithNewKeyPair();
      final other = factory.createWithNewKeyPair();
      addTearDown(signer.dispose);
      addTearDown(other.dispose);

      expect(signer.canSign, isTrue);
      expect(other.publicKey, isNot(signer.publicKey));
    });

    runSignerTestSuite(
      name: 'its signers',
      createSigner: () => factory.create(factory.generateKeyPair().$1),
      createPeer: createPeer ?? factory.createWithNewKeyPair,
      verifier: verifier,
      createReadOnlySigner: () =>
          factory.readOnly(factory.generateKeyPair().$2),
    );
  });
}

final _lowercaseHex = RegExp(r'^(?:[0-9a-f]{2})+$');

final _plaintexts = {
  'a text': 'hello',
  'unicode': r'say "hi" \o/ 你好世界 🌍',
  'a long text': 'a' * 4096,
};

final _encryptions = [
  _Encryption(
    label: 'NIP-44',
    scheme: EncryptionScheme.nip44,
    encrypt: (signer, plaintext, recipientPubkey) => signer.encryptNip44(
      plaintext: plaintext,
      recipientPubkey: recipientPubkey,
    ),
    decrypt: (signer, ciphertext, senderPubkey) =>
        signer.decryptNip44(ciphertext: ciphertext, senderPubkey: senderPubkey),
    invalidCiphertext: 'not a nip44 payload',
    authenticated: true,
  ),
  _Encryption(
    label: 'NIP-04',
    scheme: EncryptionScheme.nip04,
    // ignore: deprecated_member_use
    encrypt: (signer, plaintext, recipientPubkey) => signer.encryptNip04(
      plaintext: plaintext,
      recipientPubkey: recipientPubkey,
    ),
    decrypt: (signer, ciphertext, senderPubkey) =>
        // ignore: deprecated_member_use
        signer.decryptNip04(ciphertext: ciphertext, senderPubkey: senderPubkey),
    invalidCiphertext: 'no iv here',
    authenticated: false,
  ),
];

class _Encryption {
  const _Encryption({
    required this.label,
    required this.scheme,
    required this.encrypt,
    required this.decrypt,
    required this.invalidCiphertext,
    required this.authenticated,
  });

  final String label;
  final EncryptionScheme scheme;
  final Future<String> Function(
    NostrSigner signer,
    String plaintext,
    String recipientPubkey,
  )
  encrypt;
  final Future<String> Function(
    NostrSigner signer,
    String ciphertext,
    String senderPubkey,
  )
  decrypt;
  final String invalidCiphertext;

  /// NIP-04 has no MAC: a ciphertext of another sender may decrypt to garbage
  final bool authenticated;
}
