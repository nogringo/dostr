import 'dart:async';

import 'package:ndk/ndk.dart';
import 'package:ndk_nip85/ndk_nip85.dart';
import 'package:test/test.dart';

import '../../mocks/mock_relay.dart';
import '../../mocks/trusted_assertions_for_ndk.dart';

void main() {
  group('TrustedAssertions', () {
    late MockRelay relay;
    late Ndk ndk;
    late TrustedAssertions ta;

    // Provider keys
    final providerKey = Bip340.generatePrivateKey();
    final providerSigner = Bip340EventSigner(
      privateKey: providerKey.privateKey,
      publicKey: providerKey.publicKey,
    );

    // Subject (user being rated)
    final subjectKey = Bip340.generatePrivateKey();

    // Create a NIP-85 user assertion event (kind 30382)
    Nip01Event createNip85UserAssertion({
      required String providerPubkey,
      required String subjectPubkey,
      int rank = 85,
      int followers = 1000,
      int postCount = 500,
    }) {
      return Nip01Event(
        pubKey: providerPubkey,
        kind: Nip85Kind.user,
        tags: [
          ['d', subjectPubkey],
          ['rank', rank.toString()],
          ['followers', followers.toString()],
          ['post_cnt', postCount.toString()],
          ['t', 'nostr'],
          ['t', 'bitcoin'],
        ],
        content: '',
      );
    }

    // Create a NIP-85 event assertion event (kind 30383)
    Nip01Event createNip85EventAssertion({
      required String providerPubkey,
      required String subjectEventId,
      int? commentCount,
      int? reactionCount,
    }) {
      final tags = <List<String>>[
        ['d', subjectEventId],
      ];

      if (commentCount != null) {
        tags.add(['comment_cnt', commentCount.toString()]);
      }
      if (reactionCount != null) {
        tags.add(['reaction_cnt', reactionCount.toString()]);
      }

      return Nip01Event(
        pubKey: providerPubkey,
        kind: Nip85Kind.event,
        tags: tags,
        content: '',
      );
    }

    setUp(() async {
      relay = MockRelay(challengeOnConnect: false);
      await relay.start();

      // Create assertion event
      final assertionEvent = await providerSigner.sign(
        createNip85UserAssertion(
          providerPubkey: providerKey.publicKey,
          subjectPubkey: subjectKey.publicKey,
          rank: 89,
          followers: 2500,
          postCount: 150,
        ),
      );

      relay.events.add(assertionEvent);

      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(useIsolate: false),
          cache: MemCacheManager(),
          engine: NdkEngine.RELAY_SETS,
          bootstrapRelays: [relay.url],
        ),
      );
      await ndk.bootstrapRelaysConnected;

      ta = trustedAssertionsFor(
        ndk,
        defaultProviders: [
          Nip85TrustedProvider(
            kind: Nip85Kind.user,
            metric: Nip85Metric.rank,
            pubkey: providerKey.publicKey,
            relay: relay.url,
          ),
          Nip85TrustedProvider(
            kind: Nip85Kind.user,
            metric: Nip85Metric.followers,
            pubkey: providerKey.publicKey,
            relay: relay.url,
          ),
          Nip85TrustedProvider(
            kind: Nip85Kind.user,
            metric: Nip85Metric.postCount,
            pubkey: providerKey.publicKey,
            relay: relay.url,
          ),
        ],
      );
    });

    tearDown(() async {
      await ndk.destroy();
      await relay.stop();
    });

    test('getUserMetrics returns metrics from provider', () async {
      final metrics = await ta.getUserMetrics(subjectKey.publicKey);

      expect(metrics, isNotNull);
      expect(metrics!.pubkey, equals(subjectKey.publicKey));
      expect(metrics.providerPubkey, equals(providerKey.publicKey));
      expect(metrics.rank, equals(89));
      expect(metrics.followers, equals(2500));
      expect(metrics.postCount, equals(150));
      expect(metrics.topics, contains('nostr'));
      expect(metrics.topics, contains('bitcoin'));
    });

    test('getUserMetrics returns null for unknown pubkey', () async {
      final unknownKey = Bip340.generatePrivateKey();
      final metrics = await ta.getUserMetrics(unknownKey.publicKey);

      expect(metrics, isNull);
    });

    test('getUserMetrics filters specific metrics', () async {
      final metrics = await ta.getUserMetrics(
        subjectKey.publicKey,
        metrics: {Nip85Metric.rank, Nip85Metric.followers},
      );

      expect(metrics, isNotNull);
      expect(metrics!.rank, equals(89));
      expect(metrics.followers, equals(2500));
      // postCount should not be included when filtering
      expect(metrics.postCount, isNull);
    });

    test('getUserMetrics returns null when no providers configured', () async {
      final metrics = await trustedAssertionsFor(
        ndk,
        defaultProviders: [],
      ).getUserMetrics(subjectKey.publicKey);

      expect(metrics, isNull);
    });

    test('streamUserMetrics emits metrics and closes on cancel', () async {
      final first = Completer<Nip85UserMetrics>();
      final subscription = ta.streamUserMetrics(subjectKey.publicKey).listen((
        metrics,
      ) {
        if (!first.isCompleted) first.complete(metrics);
      });

      final metrics = await first.future.timeout(const Duration(seconds: 5));
      expect(metrics.rank, equals(89));
      expect(metrics.followers, equals(2500));

      await subscription.cancel();
      await Future.delayed(const Duration(milliseconds: 100));
      expect(relay.received('CLOSE'), isNotEmpty);
    });

    test('getUserMetrics with custom providers', () async {
      // Create a second provider
      final provider2Key = Bip340.generatePrivateKey();
      final provider2Signer = Bip340EventSigner(
        privateKey: provider2Key.privateKey,
        publicKey: provider2Key.publicKey,
      );

      final relay2 = MockRelay(challengeOnConnect: false);
      await relay2.start();

      final assertionEvent2 = await provider2Signer.sign(
        createNip85UserAssertion(
          providerPubkey: provider2Key.publicKey,
          subjectPubkey: subjectKey.publicKey,
          rank: 75,
          followers: 500,
          postCount: 50,
        ),
      );

      relay2.events.add(assertionEvent2);

      // Use custom provider instead of default
      final metrics = await ta.getUserMetrics(
        subjectKey.publicKey,
        providers: [
          Nip85TrustedProvider(
            kind: Nip85Kind.user,
            metric: Nip85Metric.rank,
            pubkey: provider2Key.publicKey,
            relay: relay2.url,
          ),
        ],
      );

      expect(metrics, isNotNull);
      expect(metrics!.rank, equals(75));
      expect(metrics.providerPubkey, equals(provider2Key.publicKey));

      await relay2.stop();
    });

    test('Nip85TrustedProvider.fromTag parses correctly', () {
      final tag = ['30382:rank', 'abc123', 'wss://relay.example.com'];
      final provider = Nip85TrustedProvider.fromTag(tag);

      expect(provider, isNotNull);
      expect(provider!.kind, equals(30382));
      expect(provider.metric, equals(Nip85Metric.rank));
      expect(provider.pubkey, equals('abc123'));
      expect(provider.relay, equals('wss://relay.example.com'));
    });

    test('Nip85TrustedProvider.toTag converts correctly', () {
      final provider = Nip85TrustedProvider(
        kind: Nip85Kind.user,
        metric: Nip85Metric.followers,
        pubkey: 'xyz789',
        relay: 'wss://test.relay',
      );

      final tag = provider.toTag();

      expect(tag, equals(['30382:followers', 'xyz789', 'wss://test.relay']));
    });

    test(
      'getEventMetrics merges metrics from multiple assertion events',
      () async {
        final eventId = 'event-id-123';

        final provider1Key = Bip340.generatePrivateKey();
        final provider1Signer = Bip340EventSigner(
          privateKey: provider1Key.privateKey,
          publicKey: provider1Key.publicKey,
        );

        final provider2Key = Bip340.generatePrivateKey();
        final provider2Signer = Bip340EventSigner(
          privateKey: provider2Key.privateKey,
          publicKey: provider2Key.publicKey,
        );

        final relay2 = MockRelay(challengeOnConnect: false);
        await relay2.start();

        final eventAssertion1 = await provider1Signer.sign(
          createNip85EventAssertion(
            providerPubkey: provider1Key.publicKey,
            subjectEventId: eventId,
            commentCount: 12,
          ),
        );

        final eventAssertion2 = await provider2Signer.sign(
          createNip85EventAssertion(
            providerPubkey: provider2Key.publicKey,
            subjectEventId: eventId,
            reactionCount: 34,
          ),
        );

        relay2.events.addAll([eventAssertion1, eventAssertion2]);

        final metrics = await ta.getEventMetrics(
          eventId,
          providers: [
            Nip85TrustedProvider(
              kind: Nip85Kind.event,
              metric: Nip85Metric.commentCount,
              pubkey: provider1Key.publicKey,
              relay: relay2.url,
            ),
            Nip85TrustedProvider(
              kind: Nip85Kind.event,
              metric: Nip85Metric.reactionCount,
              pubkey: provider2Key.publicKey,
              relay: relay2.url,
            ),
          ],
        );

        expect(metrics, isNotNull);
        expect(metrics!.commentCount, equals(12));
        expect(metrics.reactionCount, equals(34));

        await relay2.stop();
      },
    );
  });
}
