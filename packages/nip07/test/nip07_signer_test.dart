@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip07/dostr_nip07.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

@JS()
external void eval(String code);

@JS('setupNostrExtensionAsync')
external JSPromise<JSAny?> _setupNostrExtensionAsync();

Future<void> setupNostrExtension() async {
  await _setupNostrExtensionAsync().toDart;
}

const _extensionPrivateKey =
    '0a47414ecfcdda1fe8374ec28629883cdd95287e353b3fd1a536c03d953f6cc2';

void injectSetupCode() {
  eval('''
    window.setupNostrExtensionAsync = async function() {
      const nostrTools = await import('https://esm.sh/nostr-tools@2.23.0');
      const { nip04, nip44, getPublicKey, finalizeEvent } = nostrTools;

      const privateKeyHex = '$_extensionPrivateKey';

      function hexToBytes(hex) {
        const bytes = new Uint8Array(hex.length / 2);
        for (let i = 0; i < hex.length; i += 2) {
          bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
        }
        return bytes;
      }

      const privateKeyBytes = hexToBytes(privateKeyHex);
      const publicKeyHex = getPublicKey(privateKeyBytes);

      window.nostr = {
        _privkey: privateKeyBytes,
        _privkeyHex: privateKeyHex,
        _pubkey: publicKeyHex,
        _hang: false,
        _stripClientTag: false,

        setHang: function(hang) {
          this._hang = hang;
        },

        setStripClientTag: function(strip) {
          this._stripClientTag = strip;
        },

        setAccount: function(privkeyHex) {
          this._privkeyHex = privkeyHex;
          this._privkey = hexToBytes(privkeyHex);
          this._pubkey = getPublicKey(this._privkey);
        },

        getPublicKey: function() {
          if (this._hang) {
            return new Promise(() => {});
          }
          return Promise.resolve(this._pubkey);
        },

        signEvent: async function(event) {
          if (this._hang) {
            return new Promise(() => {});
          }
          const tags = this._stripClientTag
            ? event.tags.filter(function(tag) { return tag[0] !== 'client'; })
            : event.tags;
          const eventToSign = {
            kind: event.kind,
            created_at: event.created_at,
            tags: tags,
            content: event.content,
            pubkey: event.pubkey,
          };
          return finalizeEvent(eventToSign, this._privkey);
        },

        nip04: {
          encrypt: async function(recipientPubkey, plaintext) {
            return nip04.encrypt(window.nostr._privkeyHex, recipientPubkey, plaintext);
          },

          decrypt: async function(senderPubkey, ciphertext) {
            return nip04.decrypt(window.nostr._privkeyHex, senderPubkey, ciphertext);
          }
        },

        nip44: {
          encrypt: async function(recipientPubkey, plaintext) {
            const conversationKey = nip44.v2.utils.getConversationKey(window.nostr._privkey, recipientPubkey);
            return nip44.v2.encrypt(plaintext, conversationKey);
          },

          decrypt: async function(senderPubkey, ciphertext) {
            const conversationKey = nip44.v2.utils.getConversationKey(window.nostr._privkey, senderPubkey);
            return nip44.v2.decrypt(ciphertext, conversationKey);
          }
        }
      };
    };
  ''');
}

void main() {
  injectSetupCode();

  final extensionPubkey = Bip340.getPublicKey(_extensionPrivateKey);

  group('Nip07Signer', () {
    late Nip07Signer nip07Signer;
    late Bip340Signer bip340Signer;

    Nip01Event note({String? pubkey, List<List<String>> tags = const []}) =>
        Nip01Event(
          pubkey: pubkey ?? extensionPubkey,
          kind: 1,
          tags: tags,
          content: 'test content',
          createdAt: 1234567890,
        );

    setUp(() {
      nip07Signer = Nip07Signer(publicKey: extensionPubkey);
      bip340Signer = Bip340Signer(
        privateKey:
            'e4bd52924bce6a9c58d2decc7fe91b376d6a6513fc615aabc9e071f2b436b127',
        publicKey:
            '953f12b4f6966a289fde9adfc511e00a66cfa4cb9d69551dee51f3f387e8e277',
      );
    });

    tearDown(() {
      eval('window.nostr = null;');
    });

    test('canSign returns false when nostr is null', () {
      expect(Nip07Signer.isAvailable, isFalse);
      expect(nip07Signer.canSign, isFalse);
    });

    test('canSign returns true when nostr extension is available', () async {
      await setupNostrExtension();
      expect(Nip07Signer.isAvailable, isTrue);
      expect(nip07Signer.canSign, isTrue);
    });

    test('connect asks the extension for the pubkey', () async {
      await setupNostrExtension();

      final connected = await Nip07Signer.connect();
      addTearDown(connected.dispose);

      expect(connected.publicKey, extensionPubkey);
    });

    test('connect throws a StateError without an extension', () {
      expect(Nip07Signer.connect(), throwsStateError);
    });

    test('publicKey is the pubkey the signer was made with', () {
      expect(nip07Signer.publicKey, extensionPubkey);
    });

    test('sign adds id and signature to event', () async {
      await setupNostrExtension();

      final signedEvent = await nip07Signer.sign(note());
      expect(await Bip340EventVerifier().verify(signedEvent), isTrue);
    });

    test(
      'sign returns the event as signed when extension strips client tag',
      () async {
        await setupNostrExtension();
        eval('window.nostr.setStripClientTag(true);');

        final signedEvent = await nip07Signer.sign(
          note(
            tags: [
              ['client', 'dostr'],
              ['t', 'nostr'],
            ],
          ),
        );

        expect(
          signedEvent.tags,
          equals([
            ['t', 'nostr'],
          ]),
        );
        expect(await Bip340EventVerifier().verify(signedEvent), isTrue);
      },
    );

    test('sign fails when the extension signs as another account', () async {
      await setupNostrExtension();
      eval("window.nostr.setAccount('${bip340Signer.privateKey}');");

      await expectLater(
        nip07Signer.sign(note()),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('sign throws for an event of another pubkey', () async {
      await setupNostrExtension();

      await expectLater(
        nip07Signer.sign(note(pubkey: bip340Signer.publicKey)),
        throwsArgumentError,
      );
      expect(nip07Signer.pendingRequests, isEmpty);
    });

    test('encrypt NIP-04', () async {
      await setupNostrExtension();

      const message = 'Hello World';
      final encrypted = await nip07Signer.encryptNip04(
        plaintext: message,
        recipientPubkey: bip340Signer.publicKey,
      );
      final decrypted = await bip340Signer.decryptNip04(
        ciphertext: encrypted,
        senderPubkey: extensionPubkey,
      );

      expect(decrypted, equals(message));
    });

    test('decrypt NIP-04 with invalid data is rejected', () async {
      await setupNostrExtension();

      await expectLater(
        nip07Signer.decryptNip04(
          ciphertext: 'invalid_data',
          senderPubkey: bip340Signer.publicKey,
        ),
        throwsA(isA<SignerRequestRejectedException>()),
      );
    });

    test('round-trip encrypt/decrypt NIP-04', () async {
      await setupNostrExtension();

      const message = 'Hello round trip';
      final encrypted = await nip07Signer.encryptNip04(
        plaintext: message,
        recipientPubkey: extensionPubkey,
      );
      final decrypted = await nip07Signer.decryptNip04(
        ciphertext: encrypted,
        senderPubkey: extensionPubkey,
      );

      expect(decrypted, equals(message));
    });

    test('encrypt NIP-44', () async {
      await setupNostrExtension();

      const message = 'Secret Message';
      final encrypted = await nip07Signer.encryptNip44(
        plaintext: message,
        recipientPubkey: bip340Signer.publicKey,
      );
      final decrypted = await bip340Signer.decryptNip44(
        ciphertext: encrypted,
        senderPubkey: extensionPubkey,
      );

      expect(decrypted, equals(message));
    });

    test('decrypt NIP-44 with invalid data is rejected', () async {
      await setupNostrExtension();

      await expectLater(
        nip07Signer.decryptNip44(
          ciphertext: 'invalid_nip44_data',
          senderPubkey: bip340Signer.publicKey,
        ),
        throwsA(isA<SignerRequestRejectedException>()),
      );
    });

    test('round-trip encrypt/decrypt NIP-44', () async {
      await setupNostrExtension();

      const message = 'Hello NIP-44 round trip';
      final encrypted = await nip07Signer.encryptNip44(
        plaintext: message,
        recipientPubkey: extensionPubkey,
      );
      final decrypted = await nip07Signer.decryptNip44(
        ciphertext: encrypted,
        senderPubkey: extensionPubkey,
      );

      expect(decrypted, equals(message));
    });

    test('an extension without NIP-44 fails the request', () async {
      await setupNostrExtension();
      eval('window.nostr.nip44 = undefined;');

      await expectLater(
        nip07Signer.encryptNip44(
          plaintext: 'plain',
          recipientPubkey: bip340Signer.publicKey,
        ),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('every request throws a StateError without an extension', () {
      expect(
        nip07Signer.encryptNip04(
          plaintext: 'msg',
          recipientPubkey: bip340Signer.publicKey,
        ),
        throwsStateError,
      );
      expect(
        nip07Signer.decryptNip04(
          ciphertext: 'msg',
          senderPubkey: bip340Signer.publicKey,
        ),
        throwsStateError,
      );
      expect(
        nip07Signer.encryptNip44(
          plaintext: 'plain',
          recipientPubkey: bip340Signer.publicKey,
        ),
        throwsStateError,
      );
      expect(
        nip07Signer.decryptNip44(
          ciphertext: 'cipher',
          senderPubkey: bip340Signer.publicKey,
        ),
        throwsStateError,
      );
      expect(nip07Signer.sign(note()), throwsStateError);
    });

    test('decrypt NIP-04', () async {
      await setupNostrExtension();

      const message = 'Hello from BIP-340';
      final encrypted = await bip340Signer.encryptNip04(
        plaintext: message,
        recipientPubkey: extensionPubkey,
      );
      final decrypted = await nip07Signer.decryptNip04(
        ciphertext: encrypted,
        senderPubkey: bip340Signer.publicKey,
      );

      expect(decrypted, equals(message));
    });

    test('decrypt NIP-44', () async {
      await setupNostrExtension();

      const message = 'NIP-44 message from BIP-340';
      final encrypted = await bip340Signer.encryptNip44(
        plaintext: message,
        recipientPubkey: extensionPubkey,
      );
      final decrypted = await nip07Signer.decryptNip44(
        ciphertext: encrypted,
        senderPubkey: bip340Signer.publicKey,
      );

      expect(decrypted, equals(message));
    });

    test('cancelRequest returns false for non-existent request', () async {
      await setupNostrExtension();

      expect(nip07Signer.cancelRequest('non_existent_id'), isFalse);
    });

    test('pendingRequests is empty initially', () async {
      await setupNostrExtension();

      expect(nip07Signer.pendingRequests, isEmpty);
    });

    test(
      'pendingRequests contains request while operation is in progress',
      () async {
        await setupNostrExtension();
        eval('window.nostr.setHang(true);');
        addTearDown(() => eval('window.nostr.setHang(false);'));

        final event = note();
        final future = nip07Signer.sign(event);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(nip07Signer.pendingRequests, hasLength(1));
        final pending = nip07Signer.pendingRequests.first;
        expect(pending, isA<PendingSignRequest>());
        expect((pending as PendingSignRequest).event, same(event));
        expect(pending.signerPubkey, extensionPubkey);

        nip07Signer.cancelRequest(pending.id);

        try {
          await future;
        } catch (_) {}

        expect(nip07Signer.pendingRequests, isEmpty);
      },
    );

    test('cancelRequest returns true and removes pending request', () async {
      await setupNostrExtension();
      eval('window.nostr.setHang(true);');
      addTearDown(() => eval('window.nostr.setHang(false);'));

      final future = nip07Signer.sign(note());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(nip07Signer.pendingRequests, hasLength(1));
      final requestId = nip07Signer.pendingRequests.first.id;

      expect(nip07Signer.cancelRequest(requestId), isTrue);
      expect(nip07Signer.pendingRequests, isEmpty);

      Object? thrownError;
      try {
        await future;
      } catch (error) {
        thrownError = error;
      }
      expect(thrownError, isA<SignerRequestCancelledException>());
    });

    test('pendingRequestsStream emits updates', () async {
      await setupNostrExtension();
      eval('window.nostr.setHang(true);');
      addTearDown(() => eval('window.nostr.setHang(false);'));

      final emissions = <List<PendingSignerRequest>>[];
      final subscription = nip07Signer.pendingRequestsStream.listen(
        emissions.add,
      );
      addTearDown(subscription.cancel);

      final future = nip07Signer.sign(note());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(emissions.any((list) => list.length == 1), isTrue);

      final requestId = nip07Signer.pendingRequests.first.id;
      nip07Signer.cancelRequest(requestId);

      try {
        await future;
      } catch (_) {}

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emissions.last, isEmpty);
    });
  });
}
