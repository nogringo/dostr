import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip07/dostr_nip07.dart';
import 'package:dostr_nip07/src/nip07_signer.dart' show findNip07Extension;
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

import 'fake_extension.dart';

void main() {
  final windowNostr = findNip07Extension;
  final peer = Bip340Signer(
    'e4bd52924bce6a9c58d2decc7fe91b376d6a6513fc615aabc9e071f2b436b127',
  );

  late FakeExtension extension;
  late Nip07Signer signer;

  Nip01Event note({String? pubkey, List<List<String>> tags = const []}) =>
      Nip01Event(
        pubkey: pubkey ?? extensionPubkey,
        kind: 1,
        tags: tags,
        content: 'test content',
        createdAt: 1234567890,
      );

  Object? refuse(Object? answer) => throw Exception('refused');

  setUp(() {
    extension = FakeExtension();
    findNip07Extension = () => extension;
    signer = Nip07Signer(publicKey: extensionPubkey);
  });

  tearDown(() async {
    await signer.dispose();
    findNip07Extension = windowNostr;
  });

  test('the constructor throws a FormatException for an invalid pubkey', () {
    expect(() => Nip07Signer(publicKey: 'pubkey'), throwsFormatException);
    expect(
      () => Nip07Signer(publicKey: extensionPubkey.toUpperCase()),
      throwsFormatException,
    );
  });

  test('canSign tells whether there is an extension', () {
    expect(Nip07Signer.isAvailable, isTrue);
    expect(signer.canSign, isTrue);

    findNip07Extension = () => null;

    expect(Nip07Signer.isAvailable, isFalse);
    expect(signer.canSign, isFalse);
  });

  test('waitForExtension completes at once with an extension', () async {
    expect(
      await Nip07Signer.waitForExtension(timeout: const Duration(minutes: 1)),
      isTrue,
    );
  });

  group('connect', () {
    test('asks the extension for the pubkey', () async {
      final verifier = Bip340EventVerifier();
      final connected = await Nip07Signer.connect(verifier: verifier);
      addTearDown(connected.dispose);

      expect(connected.publicKey, extensionPubkey);
      expect(connected.verifier, same(verifier));
    });

    test('fails when the extension sends an invalid pubkey', () async {
      extension.tamper = (_) => 42;

      await expectLater(
        Nip07Signer.connect(),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('is rejected when the extension refuses', () async {
      extension.tamper = refuse;

      await expectLater(
        Nip07Signer.connect(),
        throwsA(isA<SignerRequestRejectedException>()),
      );
    });

    test('fails when the extension sends no pubkey in time', () async {
      extension.hang = true;

      await expectLater(
        Nip07Signer.connect(timeout: const Duration(milliseconds: 10)),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });
  });

  group('sign', () {
    test('gives the event the extension signed', () async {
      final signed = await signer.sign(note());

      expect(signed.pubkey, extensionPubkey);
      expect(signed.content, 'test content');
      expect(await Bip340EventVerifier().verify(signed), isTrue);
    });

    test('keeps the tags the extension signed', () async {
      extension.stripClientTag = true;

      final signed = await signer.sign(
        note(
          tags: [
            ['client', 'dostr'],
            ['t', 'nostr'],
          ],
        ),
      );

      expect(signed.tags, [
        ['t', 'nostr'],
      ]);
      expect(await Bip340EventVerifier().verify(signed), isTrue);
    });

    test('reads numbers that come back as doubles', () async {
      extension.tamper = (event) => {
        ...event as Map,
        'created_at': (event['created_at'] as int).toDouble(),
        'kind': (event['kind'] as int).toDouble(),
      };

      final signed = await signer.sign(note());

      expect(signed.createdAt, 1234567890);
      expect(signed.kind, 1);
      expect(signed.hasValidId, isTrue);
    });

    test('fails when the extension signs as another account', () async {
      extension.account = peer;

      await expectLater(
        signer.sign(note()),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('fails on an invalid signature when given a verifier', () async {
      final verified = Nip07Signer(
        publicKey: extensionPubkey,
        verifier: Bip340EventVerifier(),
      );
      addTearDown(verified.dispose);
      extension.tamper = (event) => {...event as Map, 'sig': '0' * 128};

      await expectLater(
        verified.sign(note()),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('is rejected when the extension refuses', () async {
      extension.tamper = refuse;

      await expectLater(
        signer.sign(note()),
        throwsA(isA<SignerRequestRejectedException>()),
      );
    });

    test('fails when the extension sends no event', () async {
      extension.tamper = (_) => null;

      await expectLater(
        signer.sign(note()),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('throws an ArgumentError for an event of another pubkey', () async {
      await expectLater(
        signer.sign(note(pubkey: peer.publicKey)),
        throwsArgumentError,
      );
      expect(signer.pendingRequests, isEmpty);
      expect(extension.requests, isEmpty);
    });
  });

  group('encryption', () {
    test('encrypts for a peer and decrypts from it with NIP-04', () async {
      final encrypted = await signer.encryptNip04(
        plaintext: 'hello',
        recipientPubkey: peer.publicKey,
      );
      expect(
        await peer.decryptNip04(
          ciphertext: encrypted,
          senderPubkey: extensionPubkey,
        ),
        'hello',
      );

      final reply = await peer.encryptNip04(
        plaintext: 'hi',
        recipientPubkey: extensionPubkey,
      );
      expect(
        await signer.decryptNip04(
          ciphertext: reply,
          senderPubkey: peer.publicKey,
        ),
        'hi',
      );
    });

    test('encrypts for a peer and decrypts from it with NIP-44', () async {
      final encrypted = await signer.encryptNip44(
        plaintext: 'hello',
        recipientPubkey: peer.publicKey,
      );
      expect(
        await peer.decryptNip44(
          ciphertext: encrypted,
          senderPubkey: extensionPubkey,
        ),
        'hello',
      );

      final reply = await peer.encryptNip44(
        plaintext: 'hi',
        recipientPubkey: extensionPubkey,
      );
      expect(
        await signer.decryptNip44(
          ciphertext: reply,
          senderPubkey: peer.publicKey,
        ),
        'hi',
      );
    });

    test('a ciphertext the extension cannot decrypt is rejected', () async {
      await expectLater(
        signer.decryptNip04(
          ciphertext: 'invalid_data',
          senderPubkey: peer.publicKey,
        ),
        throwsA(isA<SignerRequestRejectedException>()),
      );
      await expectLater(
        signer.decryptNip44(
          ciphertext: 'invalid_nip44_data',
          senderPubkey: peer.publicKey,
        ),
        throwsA(isA<SignerRequestRejectedException>()),
      );
    });

    test('fails when the extension sends no text', () async {
      extension.tamper = (_) => 42;

      await expectLater(
        signer.encryptNip44(
          plaintext: 'plain',
          recipientPubkey: peer.publicKey,
        ),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('an extension without NIP-44 fails the request', () async {
      extension.hasNip44 = false;

      await expectLater(
        signer.encryptNip44(
          plaintext: 'plain',
          recipientPubkey: peer.publicKey,
        ),
        throwsA(isA<SignerRequestFailedException>()),
      );
      expect(signer.pendingRequests, isEmpty);
    });
  });

  group('pending requests', () {
    test('a request is pending until the extension answers', () async {
      extension.hang = true;
      final event = note();

      final signed = signer.sign(event);

      final pending = signer.pendingRequests.single as PendingSignRequest;
      expect(pending.event, same(event));
      expect(pending.signerPubkey, extensionPubkey);

      await pumpEventQueue();
      extension.release();
      await signed;
      expect(signer.pendingRequests, isEmpty);
    });

    test('cancelRequest drops a pending request', () async {
      extension.hang = true;
      final signed = signer.sign(note());

      expect(signer.cancelRequest(signer.pendingRequests.single.id), isTrue);
      expect(signer.pendingRequests, isEmpty);
      await expectLater(
        signed,
        throwsA(isA<SignerRequestCancelledException>()),
      );
      expect(signer.cancelRequest('unknown'), isFalse);
    });

    test('pendingRequestsStream emits the changes', () async {
      extension.hang = true;
      final emissions = <List<PendingSignerRequest>>[];
      final subscription = signer.pendingRequestsStream.listen(emissions.add);
      addTearDown(subscription.cancel);

      final signed = signer.sign(note());
      await pumpEventQueue();
      expect(emissions.last, hasLength(1));

      extension.release();
      await signed;
      await pumpEventQueue();
      expect(emissions.last, isEmpty);
    });

    test(
      'a request cancelled in the queue never reaches the extension',
      () async {
        extension.hang = true;
        final queuing = Nip07Signer(
          publicKey: extensionPubkey,
          maxConcurrentRequests: 1,
        );
        addTearDown(queuing.dispose);

        final first = queuing.sign(note());
        final second = queuing.sign(note()).catchError((_) => note());
        await pumpEventQueue();
        queuing.cancelRequest(queuing.pendingRequests.last.id);
        extension.release();
        await first;
        await second;

        expect(extension.requests, ['signEvent']);
      },
    );

    test('request ids are unique across signers', () async {
      extension.hang = true;
      final other = Nip07Signer(publicKey: extensionPubkey);
      addTearDown(other.dispose);

      signer.sign(note()).ignore();
      other.sign(note()).ignore();

      expect(
        signer.pendingRequests.single.id,
        isNot(other.pendingRequests.single.id),
      );
    });

    test('dispose fails the requests the extension has not answered', () async {
      extension.hang = true;
      final disposed = Nip07Signer(
        publicKey: extensionPubkey,
        maxConcurrentRequests: 1,
      );

      final sent = expectLater(
        disposed.sign(note()),
        throwsA(isA<SignerRequestFailedException>()),
      );
      final queued = expectLater(
        disposed.sign(note()),
        throwsA(isA<SignerRequestFailedException>()),
      );
      await pumpEventQueue();
      await disposed.dispose();
      await sent;
      await queued;

      extension.release();
      await pumpEventQueue();
      expect(disposed.pendingRequests, isEmpty);
    });
  });
}
