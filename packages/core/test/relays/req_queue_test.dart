import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';

void main() {
  RelayManager? manager;

  final notes = [
    Filter(kinds: [1]),
  ];

  tearDown(() => manager?.closeAllTransports());

  RelayReqs open(SubscriptionLimit limit) {
    manager = newRelayManager(subscriptionLimit: limit);
    return RelayReqs(relayManager: manager!, eventVerifier: FakeVerifier());
  }

  List<String> reqIds(MockRelay relay) => [
    for (final req in relay.received('REQ')) req[1] as String,
  ];

  bool subscribed(MockRelay relay, RelayReq req) =>
      relay.openClients.any((c) => c.subscriptions.containsKey(req.id));

  Future<void> settle() => Future.delayed(const Duration(milliseconds: 200));

  test(
    'queries past the limit go out as the first ones get their EOSE',
    () async {
      final relay = await startRelay(
        answerRequests: false,
        maxSubscriptions: 4,
      );
      final reqs = open((_) => 4);

      final queries = [
        for (var i = 0; i < 5; i++) reqs.req(relays: {relay.url: notes}),
      ];
      await eventually(() => reqIds(relay).length == 4);
      await settle();
      expect(reqIds(relay), hasLength(4));

      final first = reqIds(relay).first;
      relay.sendToAll(['EOSE', first]);
      await eventually(() => reqIds(relay).length == 5);

      final messages = relay.clients.single.received;
      final close = messages.indexWhere(
        (m) => m[0] == 'CLOSE' && m[1] == first,
      );
      final last = messages.lastIndexWhere((m) => m[0] == 'REQ');
      expect(close, lessThan(last));
      expect(relay.refusedRequests, 0);
      expect(relay.clients.single.mostSubscriptions, 4);
      expect(queries.map((q) => q.id), containsAll(reqIds(relay)));
    },
  );

  test('sends in the same tick never exceed the limit', () async {
    final relay = await startRelay(maxSubscriptions: 2);
    final reqs = open((_) => 2);
    await manager!.connectRelay(dirtyUrl: relay.url);

    final queries = [
      for (var i = 0; i < 10; i++) reqs.req(relays: {relay.url: notes}),
    ];
    final outcomes = await Future.wait(queries.map((q) => q.done));

    expect(outcomes, everyElement({relay.url: isA<RelayRequestOutcome>()}));
    expect(
      outcomes.map((o) => o[relay.url]!.status),
      everyElement(RelayRequestStatus.eose),
    );
    expect(relay.refusedRequests, 0);
    expect(relay.clients.single.mostSubscriptions, 2);
  });

  test('subscriptions past their EOSE keep their slots, leaving the rest to '
      'queries', () async {
    final relay = await startRelay(maxSubscriptions: 4);
    final reqs = open((_) => 4);

    final subscriptions = [
      for (var i = 0; i < 4; i++)
        reqs.req(relays: {relay.url: notes}, closeOnEose: false),
    ];
    await eventually(
      () => subscriptions
          .take(3)
          .every(
            (s) => s.outcomes[relay.url]?.status == RelayRequestStatus.eose,
          ),
    );
    await settle();
    expect(subscribed(relay, subscriptions[3]), isFalse);

    final query = reqs.req(relays: {relay.url: notes});
    expect(await query.done, {
      relay.url: const RelayRequestOutcome(RelayRequestStatus.eose),
    });
    await settle();
    expect(subscribed(relay, subscriptions[3]), isFalse);

    await subscriptions.first.close();
    await eventually(() => subscribed(relay, subscriptions[3]));
    expect(relay.refusedRequests, 0);
  });

  test('a subscription waiting on its share does not hold back a query '
      'queued after it', () async {
    final relay = await startRelay(answerRequests: false, maxSubscriptions: 4);
    final reqs = open((_) => 4);

    for (var i = 0; i < 3; i++) {
      reqs.req(relays: {relay.url: notes}, closeOnEose: false);
    }
    final firstQuery = reqs.req(relays: {relay.url: notes});
    await eventually(() => reqIds(relay).length == 4);

    final waitingSubscription = reqs.req(
      relays: {relay.url: notes},
      closeOnEose: false,
    );
    await settle();
    final waitingQuery = reqs.req(relays: {relay.url: notes});
    await settle();
    expect(reqIds(relay), hasLength(4));

    relay.sendToAll(['EOSE', firstQuery.id]);
    await eventually(() => reqIds(relay).contains(waitingQuery.id));
    await settle();
    expect(reqIds(relay), isNot(contains(waitingSubscription.id)));
    expect(relay.refusedRequests, 0);
  });

  test(
    'closing a queued request writes no CLOSE and reports notSent',
    () async {
      final relay = await startRelay(
        answerRequests: false,
        maxSubscriptions: 1,
      );
      final reqs = open((_) => 1);

      final first = reqs.req(relays: {relay.url: notes});
      final queued = reqs.req(relays: {relay.url: notes});
      await eventually(() => reqIds(relay).length == 1);
      await settle();

      await queued.close();
      expect(await queued.done, {
        relay.url: const RelayRequestOutcome(
          RelayRequestStatus.notSent,
          failure: RelayFailure(RelayFailureKind.connectionFull),
        ),
      });

      relay.sendToAll(['EOSE', first.id]);
      await first.done;
      await settle();
      expect(reqIds(relay), [first.id]);
      expect(
        relay.received('CLOSE').map((m) => m[1]),
        isNot(contains(queued.id)),
      );
    },
  );

  test('a queued request that times out leaves the queue and reports '
      'notSent', () async {
    final relay = await startRelay(answerRequests: false, maxSubscriptions: 1);
    final reqs = open((_) => 1);

    final first = reqs.req(relays: {relay.url: notes});
    final queued = reqs.req(
      relays: {relay.url: notes},
      timeout: const Duration(milliseconds: 300),
    );

    expect(await queued.done, {
      relay.url: const RelayRequestOutcome(
        RelayRequestStatus.notSent,
        failure: RelayFailure(RelayFailureKind.connectionFull),
      ),
    });
    expect(queued.timedOut, isTrue);

    relay.sendToAll(['EOSE', first.id]);
    await first.done;
    await settle();
    expect(reqIds(relay), [first.id]);
  });

  test('a socket that comes back replays up to the limit, then drains the '
      'rest', () async {
    final relay = await startRelay(maxSubscriptions: 2);
    final reqs = open((_) => 2);

    final subscriptions = [
      for (var i = 0; i < 3; i++)
        reqs.req(relays: {relay.url: notes}, closeOnEose: false),
    ];
    await eventually(() => subscribed(relay, subscriptions[1]));

    await relay.dropConnections();
    await eventually(
      () =>
          relay.clients.length == 2 &&
          relay.clients.last.subscriptions.length == 2,
      timeout: const Duration(seconds: 10),
    );
    await settle();
    expect(subscribed(relay, subscriptions[2]), isFalse);

    await subscriptions.first.close();
    await eventually(() => subscribed(relay, subscriptions[2]));
    expect(relay.clients.last.mostSubscriptions, 2);
    expect(relay.refusedRequests, 0);
  });

  test('no REQ is written before the limit is known', () async {
    final relay = await startRelay(answerRequests: false, maxSubscriptions: 1);
    final limit = Completer<int?>();
    final reqs = open((_) => limit.future);

    reqs.req(relays: {relay.url: notes});
    reqs.req(relays: {relay.url: notes});
    await eventually(() => relay.openClients.isNotEmpty);
    await settle();
    expect(reqIds(relay), isEmpty);

    limit.complete(1);
    await eventually(() => reqIds(relay).length == 1);
    await settle();
    expect(reqIds(relay), hasLength(1));
    expect(relay.refusedRequests, 0);
  });

  test('a limit that does not come in time leaves the default', () async {
    final relay = await startRelay(answerRequests: false);
    final reqs = open((_) => Completer<int?>().future);

    for (var i = 0; i < defaultMaxSubscriptionsPerConnection + 1; i++) {
      reqs.req(relays: {relay.url: notes});
    }
    await eventually(() => relay.openClients.isNotEmpty);
    expect(reqIds(relay), isEmpty);

    await eventually(
      () => reqIds(relay).length == defaultMaxSubscriptionsPerConnection,
    );
    await settle();
    expect(reqIds(relay), hasLength(defaultMaxSubscriptionsPerConnection));
  });

  for (final answer in [null, 0, -3]) {
    test('a limit of $answer leaves the default', () async {
      final relay = await startRelay(answerRequests: false);
      final reqs = open((_) => answer);

      for (var i = 0; i < defaultMaxSubscriptionsPerConnection + 1; i++) {
        reqs.req(relays: {relay.url: notes});
      }
      await eventually(
        () => reqIds(relay).length == defaultMaxSubscriptionsPerConnection,
      );
      await settle();
      expect(reqIds(relay), hasLength(defaultMaxSubscriptionsPerConnection));
    });
  }

  test('a REQ retried after its authentication waits for a slot', () async {
    final relay = await startRelay(
      requireAuthForRequests: true,
      challengeOnConnect: false,
      maxSubscriptions: 1,
    );
    relay.events.add(signedEvent(createdAt: 1));
    final reqs = open((_) => 1);

    final queries = [
      for (var i = 0; i < 2; i++)
        reqs.req(
          relays: {relay.url: notes},
          auth: AuthPolicy.require(fakeAccount(alice)),
        ),
    ];
    final outcomes = await Future.wait(queries.map((q) => q.done));

    expect(outcomes, [
      for (final _ in queries)
        {relay.url: const RelayRequestOutcome(RelayRequestStatus.eose)},
    ]);
    expect(relay.refusedRequests, 0);
    expect(relay.clients.single.mostSubscriptions, 1);
  });

  test('a REQ whose authentication died with its socket, queued on the new '
      'one, is not given up', () async {
    final relay = await startRelay(
      requireAuthForRequests: true,
      challengeOnConnect: false,
      answerAuth: false,
      maxSubscriptions: 1,
    );
    relay.events.add(signedEvent(createdAt: 1));
    final reqs = open((_) => 1);
    final account = fakeAccount(alice);

    final queries = [
      for (var i = 0; i < 2; i++)
        reqs.req(relays: {relay.url: notes}, auth: AuthPolicy.require(account)),
    ];
    await eventually(
      () => reqIds(relay).length == 2 && relay.received('AUTH').isNotEmpty,
    );
    await settle();

    relay.answerAuth = true;
    await relay.dropConnections();
    final outcomes = await Future.wait(
      queries.map((q) => q.done),
    ).timeout(const Duration(seconds: 10));

    expect(outcomes, [
      for (final _ in queries)
        {relay.url: const RelayRequestOutcome(RelayRequestStatus.eose)},
    ]);
    expect(relay.clients, hasLength(2));
    expect(relay.refusedRequests, 0);
  });

  test('a reconnection asks for the limit again', () async {
    final relay = await startRelay();
    final asked = <String>[];
    final reqs = open((url) {
      asked.add(url);
      return 5;
    });

    final subscription = reqs.req(
      relays: {relay.url: notes},
      closeOnEose: false,
    );
    await eventually(() => subscribed(relay, subscription));
    expect(asked, [relay.url]);

    await relay.dropConnections();
    await eventually(
      () => relay.clients.length == 2 && subscribed(relay, subscription),
      timeout: const Duration(seconds: 10),
    );
    expect(asked, [relay.url, relay.url]);
  });
}
