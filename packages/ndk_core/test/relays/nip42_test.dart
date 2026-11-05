import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  late RelayManager manager;
  late RelayReqs reqs;
  late RelayPublishes publishes;

  final notes = [
    Filter(kinds: [1]),
  ];

  void build({AuthAccounts? accounts, AuthHandler? authHandler}) {
    manager = newRelayManager(accounts: accounts, authHandler: authHandler);
    reqs = RelayReqs(relayManager: manager, eventVerifier: FakeVerifier());
    publishes = RelayPublishes(relayManager: manager);
  }

  setUp(build);

  tearDown(() => manager.closeAllTransports());

  group('REQ', () {
    test('an anonymous connection never answers a challenge', () async {
      final relay = await startRelay();
      relay.events.add(signedEvent(createdAt: 1));

      final events = await reqs
          .req(
            relays: {relay.url: notes},
            auth: AuthPolicy.allow(fakeAccount(alice)),
          )
          .events
          .toList();

      expect(events, hasLength(1));
      expect(relay.clients, hasLength(1));
      expect(relay.received('AUTH'), isEmpty);
    });

    test('AuthPolicy.never leaves an auth-required REQ unserved', () async {
      final relay = await startRelay(requireAuthForRequests: true);

      final outcomes = await reqs
          .req(relays: {relay.url: notes}, auth: const AuthPolicy.never())
          .done;

      expect(outcomes[relay.url]!.status, RelayRequestStatus.closed);
      expect(outcomes[relay.url]!.message, startsWith('auth-required'));
      expect(relay.clients, hasLength(1));
      expect(relay.received('AUTH'), isEmpty);
    });

    for (final challengeOnConnect in [true, false]) {
      test(
        'AuthPolicy.allow moves a refused REQ to a bound connection '
        '(challenge ${challengeOnConnect ? 'on connect' : 'on demand'})',
        () async {
          final relay = await startRelay(
            requireAuthForRequests: true,
            challengeOnConnect: challengeOnConnect,
          );
          relay.events.add(signedEvent(createdAt: 1));

          final req = reqs.req(
            relays: {relay.url: notes},
            auth: AuthPolicy.allow(fakeAccount(alice)),
          );
          final events = await req.events.toList();

          expect(events, hasLength(1));
          expect((await req.done)[relay.url]!.status, RelayRequestStatus.eose);
          expect(relay.clients, hasLength(2));
          expect(relay.clients.first.receivedOfType('AUTH'), isEmpty);
          expect(relay.clients.last.authenticatedAs, alice);
          expect(relay.received('AUTH'), hasLength(1));
        },
      );
    }

    test('AuthPolicy.require never opens the anonymous connection', () async {
      final relay = await startRelay();
      relay.events.add(signedEvent(createdAt: 1));

      final events = await reqs
          .req(
            relays: {relay.url: notes},
            auth: AuthPolicy.require(fakeAccount(alice)),
          )
          .events
          .toList();

      expect(events, hasLength(1));
      expect(relay.clients, hasLength(1));
      await eventually(() => relay.clients.single.authenticatedAs == alice);
    });

    test(
      'AuthPolicy.require with a signer that cannot sign sends nothing',
      () async {
        final relay = await startRelay();

        final outcomes = await reqs
            .req(
              relays: {relay.url: notes},
              auth: AuthPolicy.require(fakeAccount(alice, canSign: false)),
            )
            .done;

        expect(outcomes[relay.url]!.status, RelayRequestStatus.notSent);
        expect(relay.clients, isEmpty);
      },
    );

    test('an AuthHandler that says no keeps the identity hidden', () async {
      final asked = <(String, String)>[];
      build(
        authHandler: (url, pubkey) async {
          asked.add((url, pubkey));
          return false;
        },
      );
      final relay = await startRelay(requireAuthForRequests: true);

      final outcomes = await reqs
          .req(
            relays: {relay.url: notes},
            auth: AuthPolicy.allow(fakeAccount(alice)),
          )
          .done;

      expect(asked, [(relay.url, alice)]);
      expect(outcomes[relay.url]!.status, RelayRequestStatus.closed);
      expect(relay.clients, hasLength(1));
      expect(relay.received('AUTH'), isEmpty);
    });

    group('without a policy', () {
      late FakeAuthAccounts accounts;

      setUp(() {
        accounts = FakeAuthAccounts()
          ..accounts[alice] = fakeAccount(alice)
          ..loggedPubkey = alice;
      });

      test('stays anonymous without an AuthHandler', () async {
        build(accounts: accounts);
        final relay = await startRelay(requireAuthForRequests: true);

        final outcomes = await reqs.req(relays: {relay.url: notes}).done;

        expect(outcomes[relay.url]!.status, RelayRequestStatus.closed);
        expect(relay.received('AUTH'), isEmpty);
      });

      test('authenticates as the logged account once agreed to', () async {
        build(accounts: accounts, authHandler: (_, _) async => true);
        final relay = await startRelay(requireAuthForRequests: true);
        relay.events.add(signedEvent(createdAt: 1));

        final events = await reqs
            .req(relays: {relay.url: notes})
            .events
            .toList();

        expect(events, hasLength(1));
        expect(relay.clients.last.authenticatedAs, alice);
      });
    });
  });

  group('EVENT', () {
    test(
      'AuthPolicy.allow publishes on a bound connection once refused',
      () async {
        final relay = await startRelay(requireAuthForEvents: true);
        final event = signedEvent();

        final responses = await publishes
            .publish(
              event,
              relays: [relay.url],
              auth: AuthPolicy.allow(fakeAccount(bob)),
            )
            .done;

        expect(responses.values.single.broadcastSuccessful, isTrue);
        expect(relay.events.single.id, event.id);
        expect(relay.clients.last.authenticatedAs, bob);
        expect(relay.clients.first.receivedOfType('AUTH'), isEmpty);
      },
    );

    test('an auth-required refusal once authenticated is final', () async {
      final relay = await startRelay(
        requireAuthForEvents: true,
        rejectEventsWith: 'auth-required: not on the whitelist',
      );

      final responses = await publishes
          .publish(
            signedEvent(),
            relays: [relay.url],
            auth: AuthPolicy.allow(fakeAccount(bob)),
          )
          .done;

      final response = responses.values.single;
      expect(response.okReceived, isTrue);
      expect(response.broadcastSuccessful, isFalse);
      expect(response.msg, 'auth-required: not on the whitelist');
      // anonymous, bound, and one resend if the bound EVENT raced the AUTH
      expect(relay.received('EVENT').length, lessThanOrEqualTo(3));
    });

    test('AuthPolicy.never fails an auth-required broadcast', () async {
      final relay = await startRelay(requireAuthForEvents: true);

      final responses = await publishes
          .publish(
            signedEvent(),
            relays: [relay.url],
            auth: const AuthPolicy.never(),
          )
          .done;

      expect(responses.values.single.broadcastSuccessful, isFalse);
      expect(
        responses.values.single.msg,
        'auth-required: this broadcast may not reveal an identity',
      );
      expect(relay.received('AUTH'), isEmpty);
    });

    test('AuthPolicy.require publishes on the bound connection only', () async {
      final relay = await startRelay();

      final responses = await publishes
          .publish(
            signedEvent(),
            relays: [relay.url],
            auth: AuthPolicy.require(fakeAccount(bob)),
          )
          .done;

      expect(responses.values.single.broadcastSuccessful, isTrue);
      expect(relay.clients, hasLength(1));
    });
  });
}
