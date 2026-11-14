import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_nip55/dostr_nip55.dart';
import 'package:dostr_signer/dostr_signer.dart';

class _FakeNip55Signer extends Nip55Signer {
  _FakeNip55Signer(this.response);

  final Map<dynamic, dynamic> response;

  @override
  Future<Map<dynamic, dynamic>> signEvent({
    required String currentUser,
    required String eventJson,
    String? id,
  }) async {
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const privateKey =
      'e4bd52924bce6a9c58d2decc7fe91b376d6a6513fc615aabc9e071f2b436b127';
  const publicKey =
      '953f12b4f6966a289fde9adfc511e00a66cfa4cb9d69551dee51f3f387e8e277';
  const stalePublicKey =
      'e247d5da03bab4206b4d6ef5d9db0e175e0dbf51585fa16345dd53abdd2d9259';

  group('Nip55EventSigner', () {
    test(
      'sign returns the event the external signer actually signed',
      () async {
        final externalSigner = Bip340EventSigner(
          privateKey: privateKey,
          publicKey: publicKey,
        );
        final actuallySigned = await externalSigner.sign(
          Nip01Event(
            pubKey: publicKey,
            kind: 1,
            tags: [
              ['t', 'nostr'],
            ],
            content: 'test content',
            createdAt: 1234567890,
          ),
        );

        final signer = Nip55EventSigner(
          publicKey: stalePublicKey,
          nip55Signer: _FakeNip55Signer({
            'signature': actuallySigned.sig,
            'event': actuallySigned.toJsonString(),
          }),
        );
        addTearDown(signer.dispose);

        final signedEvent = await signer.sign(
          Nip01Event(
            pubKey: stalePublicKey,
            kind: 1,
            tags: [
              ['t', 'nostr'],
            ],
            content: 'test content',
            createdAt: 1234567890,
          ),
        );

        expect(signedEvent.pubKey, equals(publicKey));
        expect(signedEvent.id, equals(actuallySigned.id));
        expect(await Bip340EventVerifier().verify(signedEvent), isTrue);
      },
    );

    test(
      'sign keeps the local event when the signer returns no event',
      () async {
        const signature = 'ab12';

        final signer = Nip55EventSigner(
          publicKey: publicKey,
          nip55Signer: _FakeNip55Signer({'signature': signature}),
        );
        addTearDown(signer.dispose);

        final event = Nip01Event(
          pubKey: publicKey,
          kind: 1,
          tags: [],
          content: 'test content',
          createdAt: 1234567890,
        );

        final signedEvent = await signer.sign(event);

        expect(signedEvent.id, equals(event.id));
        expect(signedEvent.sig, equals(signature));
      },
    );
  });

  group('Nip55EventSigner through the signer app', () {
    const channel = MethodChannel('dostr_nip55');
    const package = 'com.example.signer';

    late List<MethodCall> calls;
    late List<Completer<Object?>> answers;

    setUp(() {
      calls = [];
      answers = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            calls.add(call);
            final answer = Completer<Object?>();
            answers.add(answer);
            return answer.future;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Nip55EventSigner newSigner({
      String publicKey = publicKey,
      int maxConcurrentRequests = 100,
    }) {
      final signer = Nip55EventSigner(
        publicKey: publicKey,
        nip55Signer: const Nip55Signer(package: package),
        maxConcurrentRequests: maxConcurrentRequests,
      );
      addTearDown(signer.dispose);
      return signer;
    }

    Map<dynamic, dynamic> argumentsOf(MethodCall call) =>
        call.arguments as Map<dynamic, dynamic>;

    Future<String?> encrypt(Nip55EventSigner signer, String plaintext) => signer
        .encryptNip44(plaintext: plaintext, recipientPubKey: stalePublicKey);

    test('sends the hex pubkey as current_user for an npub login', () async {
      final signer = newSigner(publicKey: Nip19.encodePubKey(publicKey));

      final result = encrypt(signer, 'hello');
      await pumpEventQueue();

      final arguments = argumentsOf(calls.single);
      expect(arguments['type'], 'nip44_encrypt');
      expect(arguments['current_user'], publicKey);
      expect(arguments['uri_data'], 'hello');
      expect(arguments['pubkey'], stalePublicKey);
      expect(arguments['package'], package);

      answers.single.complete({'signature': 'ciphertext'});
      expect(await result, 'ciphertext');
    });

    test('lists a request as pending until the signer app answers', () async {
      final signer = newSigner();
      final emitted = <int>[];
      final subscription = signer.pendingRequestsStream.listen(
        (requests) => emitted.add(requests.length),
      );
      addTearDown(subscription.cancel);
      final event = Nip01Event(
        pubKey: publicKey,
        kind: 1,
        tags: [],
        content: 'hi',
        createdAt: 1234567890,
      );

      final signed = signer.sign(event);
      await pumpEventQueue();

      final pending = signer.pendingRequests.single;
      expect(pending.method, SignerMethod.signEvent);
      expect(pending.event!.id, event.id);
      expect(pending.signerPubkey, publicKey);
      expect(argumentsOf(calls.single)['id'], pending.id);
      expect(argumentsOf(calls.single)['uri_data'], event.toJsonString());

      answers.single.complete({'signature': 'sig'});
      expect((await signed).sig, 'sig');
      await pumpEventQueue();

      expect(signer.pendingRequests, isEmpty);
      expect(emitted, [0, 1, 0]);
    });

    test('describes each encryption request for the UI', () async {
      final signer = newSigner();

      signer.encrypt('plain04', stalePublicKey);
      signer.decrypt('cipher04', stalePublicKey);
      signer.encryptNip44(plaintext: 'plain44', recipientPubKey: publicKey);
      signer.decryptNip44(ciphertext: 'cipher44', senderPubKey: publicKey);
      await pumpEventQueue();

      expect(
        [
          for (final request in signer.pendingRequests)
            (
              request.method,
              request.plaintext,
              request.ciphertext,
              request.counterpartyPubkey,
            ),
        ],
        [
          (SignerMethod.nip04Encrypt, 'plain04', null, stalePublicKey),
          (SignerMethod.nip04Decrypt, null, 'cipher04', stalePublicKey),
          (SignerMethod.nip44Encrypt, 'plain44', null, publicKey),
          (SignerMethod.nip44Decrypt, null, 'cipher44', publicKey),
        ],
      );
      expect(
        [for (final call in calls) argumentsOf(call)['type']],
        ['nip04_encrypt', 'nip04_decrypt', 'nip44_encrypt', 'nip44_decrypt'],
      );
    });

    test('rejects with the request id when the signer app fails', () async {
      final signer = newSigner();

      final result = encrypt(signer, 'hello');
      await pumpEventQueue();
      final id = signer.pendingRequests.single.id;
      answers.single.completeError(PlatformException(code: 'USER_REJECTED'));

      await expectLater(
        result,
        throwsA(
          isA<SignerRequestRejectedException>().having(
            (e) => e.requestId,
            'requestId',
            id,
          ),
        ),
      );
      await pumpEventQueue();
      expect(signer.pendingRequests, isEmpty);
    });

    test('rejects an answer without a result', () async {
      final signer = newSigner();

      final results = [
        encrypt(signer, 'a'),
        encrypt(signer, 'b'),
        encrypt(signer, 'c'),
      ];
      await pumpEventQueue();
      answers[0].complete(null);
      answers[1].complete(<String, Object?>{});
      answers[2].complete({'signature': ''});

      for (final result in results) {
        await expectLater(
          result,
          throwsA(isA<SignerRequestRejectedException>()),
        );
      }
    });

    test('rejects a signed event that is not JSON', () async {
      final signer = newSigner();

      final signed = signer.sign(
        Nip01Event(pubKey: publicKey, kind: 1, tags: [], content: ''),
      );
      await pumpEventQueue();
      answers.single.complete({'signature': 'sig', 'event': 'not json'});

      await expectLater(signed, throwsA(isA<SignerRequestRejectedException>()));
    });

    test('cancelRequest fails the caller and drops the late answer', () async {
      final signer = newSigner();

      final result = encrypt(signer, 'hello');
      await pumpEventQueue();
      final id = signer.pendingRequests.single.id;

      expect(signer.cancelRequest(id), isTrue);
      expect(signer.pendingRequests, isEmpty);
      await expectLater(
        result,
        throwsA(
          isA<SignerRequestCancelledException>().having(
            (e) => e.requestId,
            'requestId',
            id,
          ),
        ),
      );

      answers.single.complete({'signature': 'late'});
      await pumpEventQueue();
      expect(signer.pendingRequests, isEmpty);
      expect(signer.cancelRequest(id), isFalse);
    });

    test('cancelRequest is false for an unknown request', () {
      expect(newSigner().cancelRequest('nip55_0_0'), isFalse);
    });

    test('queues requests past maxConcurrentRequests', () async {
      final signer = newSigner(maxConcurrentRequests: 1);

      final first = encrypt(signer, 'one');
      final second = encrypt(signer, 'two');
      await pumpEventQueue();

      expect(signer.pendingRequests, hasLength(2));
      expect(calls, hasLength(1));
      expect(signer.queuedRequests, 1);

      answers[0].complete({'signature': '1'});
      expect(await first, '1');
      await pumpEventQueue();

      expect(calls, hasLength(2));
      expect(argumentsOf(calls[1])['uri_data'], 'two');
      answers[1].complete({'signature': '2'});
      expect(await second, '2');
    });

    test('a request cancelled in the queue never reaches the app', () async {
      final signer = newSigner(maxConcurrentRequests: 1);

      final first = encrypt(signer, 'one');
      final second = encrypt(signer, 'two');
      await pumpEventQueue();

      expect(signer.cancelRequest(signer.pendingRequests.last.id), isTrue);
      await expectLater(
        second,
        throwsA(isA<SignerRequestCancelledException>()),
      );

      answers.single.complete({'signature': '1'});
      expect(await first, '1');
      await pumpEventQueue();

      expect(calls, hasLength(1));
      expect(signer.pendingRequests, isEmpty);
      expect(signer.queuedRequests, 0);
    });

    test(
      'dispose rejects the queued requests and lets the running one finish',
      () async {
        final signer = Nip55EventSigner(
          publicKey: publicKey,
          nip55Signer: const Nip55Signer(),
          maxConcurrentRequests: 1,
        );

        final first = encrypt(signer, 'one');
        final queued = encrypt(signer, 'two');
        await pumpEventQueue();
        await signer.dispose();

        await expectLater(
          queued,
          throwsA(isA<SignerRequestRejectedException>()),
        );
        answers.single.complete({'signature': '1'});
        expect(await first, '1');
        await pumpEventQueue();
      },
    );
  });
}
