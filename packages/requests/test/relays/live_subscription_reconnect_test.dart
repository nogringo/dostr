import '../mocks/requests_client.dart';
import 'dart:async';

import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/mock_event_verifier.dart';

void main() {
  late MockRelay mockRelay;

  setUp(() async {
    mockRelay = MockRelay(name: 'live-subscription-test-relay', port: 4070);
    await mockRelay.start();
  });

  tearDown(() async {
    await mockRelay.stop();
  });

  Future<void> waitForSubscriptionRegistration() async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (mockRelay.activeSubscriptionCount > 0) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 25));
    }
    throw TimeoutException('MockRelay did not register the subscription.');
  }

  test('live subscription resumes after relay closes the socket', () async {
    final keyPair = Bip340.generatePrivateKey();

    final ndkA = RequestsClient(
      cache: MemCacheManager(),
      eventVerifier: MockEventVerifier(),
      bootstrapRelays: [mockRelay.url],
    );
    addTearDown(ndkA.destroy);

    final ndkB = RequestsClient(
      cache: MemCacheManager(),
      eventVerifier: MockEventVerifier(),
      bootstrapRelays: [mockRelay.url],
    );
    addTearDown(ndkB.destroy);

    final eventAfterReconnect = Completer<Nip01Event>();
    final subscription = ndkA.requests.subscription(
      filter: Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [keyPair.publicKey],
      ),
    );

    subscription.stream.listen((event) {
      if (!eventAfterReconnect.isCompleted) {
        eventAfterReconnect.complete(event);
      }
    });

    await waitForSubscriptionRegistration();

    // Relay-side disconnect: the server stays up, only the sockets die.
    await mockRelay.dropConnections();

    // NDK A must reconnect and re-send its in-flight REQ on its own.
    await waitForSubscriptionRegistration();

    final event = Nip01Event(
      pubKey: keyPair.publicKey,
      kind: Nip01Event.kTextNoteKind,
      tags: [],
      content: 'event after reconnect',
    );
    final signedEvent = Bip340.signEvent(
      event: event,
      privateKey: keyPair.privateKey!,
    );

    await ndkB.relayPublishes
        .publish(signedEvent, relays: [mockRelay.url])
        .done;

    final received = await eventAfterReconnect.future.timeout(
      Duration(seconds: 5),
      onTimeout: () => throw TimeoutException(
        'NDK A did not receive events after the relay closed the socket.',
      ),
    );

    expect(received.id, equals(signedEvent.id));
    expect(received.content, equals('event after reconnect'));
  });
}
