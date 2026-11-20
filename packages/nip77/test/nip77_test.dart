import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:dostr_nip77/dostr_nip77.dart';
import 'package:test/test.dart';

final String alice = 'a' * 64;

/// what the relays of these tests hold and the client does not
final String onRelay = 'e' * 64;

String idOf(int i) => i.toRadixString(16).padLeft(64, '0');

/// Signs with a fake signature, which [MockRelay] does not check.
class TestSigner implements NostrSigner {
  TestSigner(
    this.publicKey, {
    this.signable = true,
    this.signDelay,
    this.refuse = false,
  });

  @override
  final String publicKey;
  final bool signable;
  final Duration? signDelay;
  final bool refuse;
  int signAttempts = 0;

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    signAttempts++;
    final delay = signDelay;
    if (delay != null) await Future<void>.delayed(delay);
    if (refuse) throw StateError('the user refused to sign');
    return event.copyWith(sig: 'f' * 128);
  }

  @override
  bool get canSign => signable;

  @override
  Stream<List<PendingSignerRequest>> get pendingRequestsStream =>
      Stream.value(const []);

  @override
  List<PendingSignerRequest> get pendingRequests => const [];

  @override
  bool cancelRequest(String requestId) => false;

  @override
  Future<void> dispose() async {}

  @override
  Future<String> decryptNip04({
    required String ciphertext,
    required String senderPubkey,
  }) => throw UnimplementedError();

  @override
  Future<String> encryptNip04({
    required String plaintext,
    required String recipientPubkey,
  }) => throw UnimplementedError();

  @override
  Future<String> encryptNip44({
    required String plaintext,
    required String recipientPubkey,
  }) => throw UnimplementedError();

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) => throw UnimplementedError();
}

/// Waits until [condition] holds, failing the test after [timeout].
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late RelayManager manager;
  late Nip77 nip77;
  final local = <String, int>{};
  var loads = 0;

  final notes = Filter(kinds: [1], authors: [alice]);

  setUp(() {
    local.clear();
    loads = 0;
    manager = RelayManager(
      nostrTransportFactory: webSocketTransportFactory(pingInterval: null),
    );
    nip77 = Nip77(
      relayManager: manager,
      loadEventIds: (_) async {
        loads++;
        return [
          for (final entry in local.entries)
            (id: entry.key, createdAt: entry.value),
        ];
      },
    );
  });

  tearDown(() => manager.dispose());

  /// A relay holding [onRelay], so a reconciliation that ran is told apart
  /// from one that did not.
  Future<MockRelay> startRelay({
    bool requireAuth = false,
    bool refuseWithClosed = false,
    Duration? delayResponse,
  }) async {
    final relay = MockRelay(
      requireAuthForNegentropy: requireAuth,
      refuseNegentropyWithClosed: refuseWithClosed,
      // the relay only challenges once it refuses, which is what `allow` waits
      // for, so the challenge has to be offered on every connection
      challengeOnConnect: requireAuth,
    );
    relay.negentropyItems[onRelay] = 1000;
    await relay.start(delayResponse: delayResponse);
    addTearDown(relay.stop);
    return relay;
  }

  group('NIP-42', () {
    test('require reconciles on a bound connection from the start', () async {
      final relay = await startRelay(requireAuth: true);

      final result = await nip77
          .reconcile(
            relayUrl: relay.url,
            filter: notes,
            auth: AuthPolicy.require(TestSigner(alice)),
          )
          .future;

      expect(result.needIds, [onRelay]);
      expect(relay.connectionsAuthenticatedAs(alice), 1);
      expect(relay.negOpensAuthenticatedAs(alice), isNotEmpty);
      expect(
        relay.negOpensNotAuthenticatedAs(alice),
        isEmpty,
        reason: 'require never opens a negotiation on the anonymous connection',
      );
    });

    test('allow reconciles after the relay refuses with NEG-ERR', () async {
      final relay = await startRelay(requireAuth: true);

      final result = await nip77
          .reconcile(
            relayUrl: relay.url,
            filter: notes,
            auth: AuthPolicy.allow(TestSigner(alice)),
          )
          .future;

      expect(result.needIds, [onRelay]);
      expect(relay.connectionsAuthenticatedAs(alice), 1);
      expect(
        relay.negOpensNotAuthenticatedAs(alice),
        isNotEmpty,
        reason: 'allow tries the anonymous connection before authenticating',
      );
    });

    test('allow reconciles after the relay refuses with CLOSED', () async {
      final relay = await startRelay(requireAuth: true, refuseWithClosed: true);

      final result = await nip77
          .reconcile(
            relayUrl: relay.url,
            filter: notes,
            auth: AuthPolicy.allow(TestSigner(alice)),
          )
          .future;

      expect(result.needIds, [onRelay]);
      expect(relay.connectionsAuthenticatedAs(alice), 1);
    });

    for (final (name, auth) in [
      ('never', const AuthPolicy.never()),
      ('no policy', null),
    ]) {
      test('$name stays unattributable when a relay refuses', () async {
        final relay = await startRelay(requireAuth: true);

        await expectLater(
          nip77
              .reconcile(relayUrl: relay.url, filter: notes, auth: auth)
              .future,
          throwsA(isA<Nip77AuthRequiredException>()),
        );
        expect(relay.connectionsAuthenticatedAs(alice), 0);
        expect(relay.received('AUTH'), isEmpty);
      });
    }

    test(
      'require with a signer that cannot sign throws and sends nothing',
      () async {
        final relay = await startRelay(requireAuth: true);

        expect(
          () => nip77.reconcile(
            relayUrl: relay.url,
            filter: notes,
            auth: AuthPolicy.require(TestSigner(alice, signable: false)),
          ),
          throwsA(isA<Nip77AuthUnavailableException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(relay.clients, isEmpty);
      },
    );

    test('a slow signer does not spend the open timeout', () async {
      final relay = await startRelay(requireAuth: true);

      // the signature alone outlasts the open timeout, so this only reconciles
      // if waiting on the signer does not count against it
      final result = await nip77
          .reconcile(
            relayUrl: relay.url,
            filter: notes,
            auth: AuthPolicy.require(
              TestSigner(alice, signDelay: const Duration(milliseconds: 600)),
            ),
            openTimeout: const Duration(milliseconds: 300),
          )
          .future;

      expect(result.needIds, [onRelay]);
      expect(relay.connectionsAuthenticatedAs(alice), 1);
    });

    for (final (name, policy) in [
      ('require', AuthPolicy.require),
      ('allow', AuthPolicy.allow),
    ]) {
      test('a refused signature ends the reconciliation ($name)', () async {
        final relay = await startRelay(requireAuth: true);
        final signer = TestSigner(alice, refuse: true);

        await expectLater(
          nip77
              .reconcile(
                relayUrl: relay.url,
                filter: notes,
                auth: policy(signer),
              )
              .future,
          throwsA(isA<Nip77AuthRequiredException>()),
        );
        expect(relay.connectionsAuthenticatedAs(alice), 0);
        expect(signer.signAttempts, greaterThan(0));
      });
    }
  });

  group('timeouts', () {
    const itemCount = 4000;

    /// the client holds every other event, which takes more than one round
    Future<MockRelay> largeRelay({Duration? delayResponse}) async {
      final relay = await startRelay(delayResponse: delayResponse);
      for (var i = 0; i < itemCount; i++) {
        relay.negentropyItems[idOf(i)] = 0;
      }
      return relay;
    }

    final localIds = [
      for (var i = 0; i < itemCount; i += 2) (id: idOf(i), createdAt: 0),
    ];

    test('a reconciliation that keeps progressing has no deadline', () async {
      final relay = await largeRelay(
        delayResponse: const Duration(milliseconds: 300),
      );

      final stopwatch = Stopwatch()..start();
      final result = await nip77
          .reconcile(
            relayUrl: relay.url,
            filter: notes,
            localIds: localIds,
            openTimeout: const Duration(milliseconds: 500),
            idleTimeout: const Duration(milliseconds: 500),
          )
          .future;

      expect(result.needIds, hasLength(itemCount ~/ 2 + 1));
      expect(relay.negentropyAnswers, greaterThanOrEqualTo(2));
      expect(
        stopwatch.elapsed,
        greaterThan(const Duration(milliseconds: 500)),
        reason: 'the session outlived both timeouts, so neither caps it',
      );
    });

    test('a relay that never answers NEG-OPEN times out', () async {
      final relay = await largeRelay();
      relay.silenceNegentropyAfter = 0;

      await expectLater(
        nip77
            .reconcile(
              relayUrl: relay.url,
              filter: notes,
              localIds: localIds,
              openTimeout: const Duration(milliseconds: 300),
            )
            .future,
        throwsA(
          isA<Nip77TimeoutException>()
              .having((e) => e.openUnanswered, 'openUnanswered', isTrue)
              .having(
                (e) => e.timeout,
                'timeout',
                const Duration(milliseconds: 300),
              ),
        ),
      );
    });

    test('a relay that goes silent between two rounds times out', () async {
      final relay = await largeRelay();
      relay.silenceNegentropyAfter = 1;

      await expectLater(
        nip77
            .reconcile(
              relayUrl: relay.url,
              filter: notes,
              localIds: localIds,
              idleTimeout: const Duration(milliseconds: 300),
            )
            .future,
        throwsA(
          isA<Nip77TimeoutException>()
              .having((e) => e.openUnanswered, 'openUnanswered', isFalse)
              .having(
                (e) => e.timeout,
                'timeout',
                const Duration(milliseconds: 300),
              ),
        ),
      );
    });
  });

  test('reconciliations started together each get their own id', () async {
    final relays = [await startRelay(), await startRelay()];

    final responses = [
      for (var i = 0; i < 6; i++)
        nip77.reconcile(relayUrl: relays[i % 2].url, filter: notes),
    ];
    final results = await Future.wait(responses.map((r) => r.future));

    expect(results.map((r) => r.needIds), everyElement([onRelay]));
    expect(responses.map((r) => r.subscriptionId).toSet(), hasLength(6));
  });

  group('refusals', () {
    Future<MockRelay> refusingRelay(
      List<dynamic> Function(String id) answer,
    ) async {
      final relay = await startRelay();
      relay.onMessage = (client, message) {
        if (message[0] != 'NEG-OPEN') return false;
        client.send(answer(message[1] as String));
        return true;
      };
      return relay;
    }

    test('a blocked NEG-ERR gives its code and record limit', () async {
      final relay = await refusingRelay(
        (id) => ['NEG-ERR', id, 'blocked: this query is too big', 5000],
      );

      await expectLater(
        nip77.reconcile(relayUrl: relay.url, filter: notes).future,
        throwsA(
          isA<Nip77RefusedException>()
              .having((e) => e.code, 'code', 'blocked')
              .having((e) => e.maxRecords, 'maxRecords', 5000),
        ),
      );
    });

    test('a closed NEG-ERR is a refusal, not a missing NIP-77', () async {
      final relay = await refusingRelay(
        (id) => ['NEG-ERR', id, 'closed: you took too long to respond!'],
      );

      await expectLater(
        nip77.reconcile(relayUrl: relay.url, filter: notes).future,
        throwsA(
          isA<Nip77RefusedException>()
              .having((e) => e.code, 'code', 'closed')
              .having((e) => e.maxRecords, 'maxRecords', isNull),
        ),
      );
    });

    test('a CLOSED that asks for no identity is a refusal', () async {
      final relay = await refusingRelay(
        (id) => ['CLOSED', id, 'error: shutting down'],
      );

      await expectLater(
        nip77.reconcile(relayUrl: relay.url, filter: notes).future,
        throwsA(
          isA<Nip77RefusedException>().having((e) => e.code, 'code', 'error'),
        ),
      );
    });

    test(
      'one that only mentions an identity reveals none under allow',
      () async {
        final relay = await refusingRelay(
          (id) => ['NEG-ERR', id, 'blocked: restricted, see auth-required'],
        );

        await expectLater(
          nip77
              .reconcile(
                relayUrl: relay.url,
                filter: notes,
                auth: AuthPolicy.allow(TestSigner(alice)),
              )
              .future,
          throwsA(
            isA<Nip77RefusedException>().having(
              (e) => e.code,
              'code',
              'blocked',
            ),
          ),
        );
        expect(relay.clients, hasLength(1), reason: 'no bound connection');
        expect(relay.received('AUTH'), isEmpty);
      },
    );

    test('a restricted one on a bound connection is a refusal', () async {
      final relay = await startRelay(requireAuth: true);
      relay.onMessage = (client, message) {
        if (message[0] != 'NEG-OPEN') return false;
        client.send(['NEG-ERR', message[1], 'restricted: not a member']);
        return true;
      };

      await expectLater(
        nip77
            .reconcile(
              relayUrl: relay.url,
              filter: notes,
              auth: AuthPolicy.require(TestSigner(alice)),
            )
            .future,
        throwsA(
          isA<Nip77RefusedException>().having(
            (e) => e.code,
            'code',
            'restricted',
          ),
        ),
      );
      expect(relay.receivedNegOpens, hasLength(1), reason: 'not tried again');
    });
  });

  group('several Nip77', () {
    test('share a RelayManager, each getting its answers', () async {
      final relay = await startRelay();
      final other = Nip77(relayManager: manager, loadEventIds: (_) async => []);
      addTearDown(other.dispose);

      final results = await Future.wait([
        nip77.reconcile(relayUrl: relay.url, filter: notes).future,
        other
            .reconcile(
              relayUrl: relay.url,
              filter: notes,
              openTimeout: const Duration(seconds: 2),
            )
            .future,
      ]);

      expect(results.map((r) => r.needIds), everyElement([onRelay]));
    });

    test('dispose closes the reconciliations and refuses new ones', () async {
      final relay = await startRelay();
      relay.silenceNegentropyAfter = 0;

      final response = nip77.reconcile(relayUrl: relay.url, filter: notes);
      await eventually(() => relay.receivedNegOpens.isNotEmpty);
      nip77.dispose();

      expect((await response.future).isComplete, isFalse);
      await eventually(() => relay.received('NEG-CLOSE').isNotEmpty);
      expect(
        () => nip77.reconcile(relayUrl: relay.url, filter: notes),
        throwsStateError,
      );
    });
  });

  group('connection loss', () {
    Future<(MockRelay, Nip77Response)> waitingOnRelay() async {
      final relay = await startRelay();
      relay.silenceNegentropyAfter = 0;
      final response = nip77.reconcile(
        relayUrl: relay.url,
        filter: notes,
        openTimeout: const Duration(minutes: 1),
      );
      await eventually(() => relay.receivedNegOpens.isNotEmpty);
      return (relay, response);
    }

    final lost = throwsA(
      isA<Nip77ConnectionException>().having((e) => e.lost, 'lost', isTrue),
    );

    test('a dropped socket fails the reconciliation at once', () async {
      final (relay, response) = await waitingOnRelay();
      final failed = expectLater(response.future, lost);

      await relay.dropConnections();

      await failed;
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('a closed connection fails the reconciliation at once', () async {
      final (relay, response) = await waitingOnRelay();
      final failed = expectLater(response.future, lost);

      await manager.closeConnection(RelayConnectionKey.anonymous(relay.url));

      await failed;
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('NOTICE', () {
    test('one that refuses an unanswered NEG-OPEN fails it', () async {
      final relay = await startRelay();
      relay.onMessage = (client, message) {
        if (message[0] != 'NEG-OPEN') return false;
        client.send(['NOTICE', 'ERROR: unknown command NEG-OPEN']);
        return true;
      };

      await expectLater(
        nip77.reconcile(relayUrl: relay.url, filter: notes).future,
        throwsA(isA<Nip77NotSupportedException>()),
      );
    });

    test(
      'one after the first answer leaves the reconciliation running',
      () async {
        final relay = await startRelay();
        for (var i = 0; i < 4000; i++) {
          relay.negentropyItems[idOf(i)] = 0;
        }
        relay.onMessage = (client, message) {
          if (message[0] == 'NEG-MSG') {
            client.send(['NOTICE', 'unsupported kind']);
          }
          return false;
        };

        final result = await nip77
            .reconcile(
              relayUrl: relay.url,
              filter: notes,
              localIds: [
                for (var i = 0; i < 4000; i += 2) (id: idOf(i), createdAt: 0),
              ],
            )
            .future;

        expect(result.isComplete, isTrue);
        expect(result.needIds, hasLength(2001));
      },
    );

    test('one on another connection to the relay leaves it running', () async {
      final relay = await startRelay();
      await manager.connectRelay(relay.url);
      relay.onMessage = (client, message) {
        if (message[0] != 'NEG-OPEN') return false;
        for (final other in relay.openClients) {
          if (!identical(other, client)) {
            other.send(['NOTICE', 'unsupported: NEG-OPEN']);
          }
        }
        final answer = NegentropyEncoder.respond(
          NegentropyEncoder.hexToBytes(message[3] as String),
          [NegentropyItem.fromHex(timestamp: 1000, idHex: onRelay)],
        );
        Timer(const Duration(milliseconds: 200), () {
          client.send([
            'NEG-MSG',
            message[1],
            NegentropyEncoder.bytesToHex(answer),
          ]);
        });
        return true;
      };

      final result = await nip77
          .reconcile(
            relayUrl: relay.url,
            filter: notes,
            auth: AuthPolicy.require(TestSigner(alice)),
          )
          .future;

      expect(result.needIds, [onRelay]);
      expect(relay.openClients, hasLength(2));
    });
  });

  group('outcomes', () {
    test('close ends with what was found and says so', () async {
      final relay = await startRelay();
      relay.silenceNegentropyAfter = 0;

      final response = nip77.reconcile(relayUrl: relay.url, filter: notes);
      await eventually(() => relay.receivedNegOpens.isNotEmpty);
      nip77.close(response.subscriptionId);

      final result = await response.future;
      expect(result.isComplete, isFalse);
      await eventually(() => relay.received('NEG-CLOSE').isNotEmpty);
    });

    test('a converged reconciliation says it is complete', () async {
      final relay = await startRelay();

      final result = await nip77
          .reconcile(relayUrl: relay.url, filter: notes)
          .future;

      expect(result.isComplete, isTrue);
    });

    test('the streams keep every id for a late listener', () async {
      final relay = await startRelay();
      for (var i = 1; i <= 3; i++) {
        relay.negentropyItems[idOf(i)] = 2000 + i;
        local[idOf(10 + i)] = 3000 + i;
      }

      final response = nip77.reconcile(relayUrl: relay.url, filter: notes);
      final result = await response.future;

      expect(await response.needStream.toList(), result.needIds);
      expect(result.needIds, hasLength(4));
      expect(await response.haveStream.toList(), result.haveIds);
      expect(result.haveIds, hasLength(3));
    });

    test('the streams close without an error when the future fails', () async {
      final relay = await startRelay();
      relay.silenceNegentropyAfter = 0;

      final response = nip77.reconcile(
        relayUrl: relay.url,
        filter: notes,
        openTimeout: const Duration(milliseconds: 200),
      );

      await expectLater(response.future, throwsA(isA<Nip77TimeoutException>()));
      expect(await response.needStream.toList(), isEmpty);
      expect(await response.haveStream.toList(), isEmpty);
    });

    test(
      'a relay that cannot be reached fails with a connection error',
      () async {
        final unreachable = MockRelay();

        await expectLater(
          nip77.reconcile(relayUrl: unreachable.url, filter: notes).future,
          throwsA(isA<Nip77ConnectionException>()),
        );
      },
    );

    test('an unreadable NEG-MSG fails it and closes the negotiation', () async {
      final relay = await startRelay();
      relay.onMessage = (client, message) {
        if (message[0] != 'NEG-OPEN') return false;
        client.send(['NEG-MSG', message[1], 'zz']);
        return true;
      };

      await expectLater(
        nip77.reconcile(relayUrl: relay.url, filter: notes).future,
        throwsA(isA<Nip77MalformedMessageException>()),
      );
      await eventually(() => relay.received('NEG-CLOSE').isNotEmpty);
    });

    test('every failure is a Nip77Exception', () async {
      final relay = await startRelay();
      relay.silenceNegentropyAfter = 0;

      await expectLater(
        nip77
            .reconcile(
              relayUrl: relay.url,
              filter: notes,
              openTimeout: const Duration(milliseconds: 100),
            )
            .future,
        throwsA(isA<Nip77Exception>()),
      );
    });
  });

  group('local events', () {
    test('localIds are reconciled at their creation time', () async {
      final relay = await startRelay();
      relay.negentropyItems[idOf(2)] = 2000;

      final result = await nip77
          .reconcile(
            relayUrl: relay.url,
            filter: notes,
            localIds: [
              (id: onRelay, createdAt: 1000),
              (id: idOf(3), createdAt: 3000),
            ],
          )
          .future;

      expect(result.needIds, [idOf(2)]);
      expect(result.haveIds, [idOf(3)]);
      expect(loads, 0, reason: 'localIds replace loadEventIds');
    });

    test('without localIds, loadEventIds gives the local events', () async {
      final relay = await startRelay();
      local[onRelay] = 1000;

      final result = await nip77
          .reconcile(relayUrl: relay.url, filter: notes)
          .future;

      expect(result.needIds, isEmpty);
      expect(result.haveIds, isEmpty);
      expect(loads, 1);
    });

    test(
      'a localIds entry that is not an event throws and sends nothing',
      () async {
        final relay = await startRelay();

        for (final entry in [
          (id: 'xyz', createdAt: 1000),
          (id: onRelay, createdAt: -1),
        ]) {
          expect(
            () => nip77.reconcile(
              relayUrl: relay.url,
              filter: notes,
              localIds: [entry],
            ),
            throwsArgumentError,
            reason: '$entry',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(relay.clients, isEmpty);
      },
    );

    test('an entry of loadEventIds that is not an event fails it', () async {
      final relay = await startRelay();
      local['xyz'] = 1000;

      await expectLater(
        nip77.reconcile(relayUrl: relay.url, filter: notes).future,
        throwsArgumentError,
      );
    });
  });

  group('frame size limit', () {
    test('keeps every NEG-MSG within it and reconciles exactly', () async {
      final relay = await startRelay();
      for (var i = 0; i < 6000; i++) {
        if (i % 3 != 1) relay.negentropyItems[idOf(i)] = 1700000000 + i ~/ 7;
      }

      final result = await nip77
          .reconcile(
            relayUrl: relay.url,
            filter: notes,
            frameSizeLimit: 4096,
            localIds: [
              for (var i = 0; i < 6000; i++)
                if (i % 3 != 0) (id: idOf(i), createdAt: 1700000000 + i ~/ 7),
            ],
          )
          .future;

      expect(result.needIds.toSet(), hasLength(2001));
      expect(result.needIds, hasLength(2001), reason: 'no repeats');
      expect(result.haveIds.toSet(), hasLength(2000));
      expect(result.haveIds, hasLength(2000), reason: 'no repeats');
      final sent = relay.received('NEG-MSG');
      expect(sent, isNotEmpty);
      for (final message in sent) {
        expect((message[2] as String).length, lessThanOrEqualTo(2 * 4096));
      }
    });

    test(
      'a limit too small to hold one range throws and sends nothing',
      () async {
        final relay = await startRelay();

        expect(
          () => nip77.reconcile(
            relayUrl: relay.url,
            filter: notes,
            frameSizeLimit: 1000,
          ),
          throwsArgumentError,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(relay.clients, isEmpty);
      },
    );
  });
}
