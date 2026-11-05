import 'dart:async';

import 'package:ndk_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:ndk/domain_layer/entities/nip_65.dart';
import 'package:ndk/domain_layer/entities/pubkey_mapping.dart';
import 'package:ndk/domain_layer/entities/read_write_marker.dart';
import 'package:ndk/domain_layer/entities/user_relay_list.dart';
import 'package:ndk/domain_layer/usecases/jit_engine/jit_request_plan.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'package:ndk/domain_layer/usecases/relay_sets_engine.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import '../../../../cashu/test/mocks/mock_event_verifier.dart';
import '../../mocks/mock_relay.dart';

/// A second REQ with the same id replaces the first on the relay (NIP-01), so
/// whatever an engine routes to one relay has to travel in a single REQ.
void main() {
  final a = Bip340.generatePrivateKey();
  final b = Bip340.generatePrivateKey();

  Nip01Event note(KeyPair key) => Bip340.signEvent(
    event: Nip01Event(
      pubKey: key.publicKey,
      kind: Nip01Event.kTextNodeKind,
      tags: [],
      content: 'live note',
    ),
    privateKey: key.privateKey!,
  );

  test(
    'a JIT subscription keeps every pubkey it routed to one relay',
    () async {
      final relay = MockRelay(name: 'relay', signEvents: false);
      await relay.startServer();
      addTearDown(relay.stopServer);

      // a is covered by the relay's NIP-65 entry, b by nothing, so b is blasted
      // to the same bootstrap relay
      final cache = MemCacheManager();
      await cache.saveUserRelayLists([
        UserRelayList.fromNip65(
          Nip65.fromMap(a.publicKey, {relay.url: ReadWriteMarker.readWrite}),
        ),
      ]);
      final ndk = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: cache,
          engine: NdkEngine.JIT,
          bootstrapRelays: [relay.url],
        ),
      );
      addTearDown(ndk.destroy);
      final publisher = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [],
        ),
      );
      addTearDown(publisher.destroy);

      final subscription = ndk.requests.subscription(
        filter: Filter(
          kinds: [Nip01Event.kTextNodeKind],
          authors: [a.publicKey, b.publicKey],
        ),
        desiredCoverage: 1,
      );
      final authors = <String>{};
      final both = Completer<void>();
      subscription.stream.listen((event) {
        authors.add(event.pubKey);
        if (authors.length == 2 && !both.isCompleted) both.complete();
      });
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (relay.activeSubscriptionCount == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      for (final key in [a, b]) {
        await publisher.broadcast
            .broadcast(nostrEvent: note(key), specificRelays: [relay.url])
            .broadcastDoneFuture;
      }

      await both.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => fail('live notes only arrived from $authors'),
      );
    },
  );

  test('a relay set relay gets every filter that maps to it', () async {
    const url = 'wss://relay.example.com';
    final manager = RelayManager(
      nostrTransportFactory: WebSocketClientNostrTransportFactory(),
    );
    final engine = RelaySetsEngine(
      relayManager: manager,
      cacheManager: MemCacheManager(),
      bootstrapRelays: [],
    );
    final relaySet = RelaySet(
      name: 'test',
      pubKey: a.publicKey,
      relaysMap: {
        url: [
          PubkeyMapping(
            pubKey: a.publicKey,
            rwMarker: ReadWriteMarker.readWrite,
          ),
        ],
      },
      direction: RelayDirection.outbox,
    );

    final sent = <String, List<Filter>>{};
    await engine.route(
      [
        Filter(kinds: [Nip01Event.kTextNodeKind], authors: [a.publicKey]),
        Filter(kinds: [Metadata.kKind], authors: [a.publicKey]),
      ],
      (relayUrl, filters) {
        expect(sent, isNot(contains(relayUrl)));
        sent[relayUrl] = filters;
      },
      relaySet: relaySet,
      desiredCoverage: 2,
    );

    expect(sent.keys, [url]);
    expect(sent[url]!.map((filter) => filter.kinds), [
      [Nip01Event.kTextNodeKind],
      [Metadata.kKind],
    ]);
  });

  group('JitRequestPlan', () {
    final filter = Filter(
      kinds: [Nip01Event.kTextNodeKind],
      authors: [a.publicKey, b.publicKey],
    );

    test('merges what was added for a relay into one filter', () {
      final sent = <String, List<Filter>>{};
      final plan = JitRequestPlan((url, filters) => sent[url] = filters);

      plan.addPubkeys('wss://relay.example.com', filter, [a.publicKey]);
      plan.addPubkeys('wss://relay.example.com/', filter, [b.publicKey]);
      plan.flush();

      expect(sent.keys, ['wss://relay.example.com']);
      expect(sent['wss://relay.example.com']!.single.authors, [
        a.publicKey,
        b.publicKey,
      ]);
    });

    test('a whole filter wins over pubkeys added for the same relay', () {
      final sent = <String, List<Filter>>{};
      final plan = JitRequestPlan((url, filters) => sent[url] = filters);

      plan.addFilter('wss://relay.example.com', filter);
      plan.addPubkeys('wss://relay.example.com', filter, [a.publicKey]);
      plan.flush();

      expect(sent['wss://relay.example.com'], [same(filter)]);
    });

    test('never sends to a relay twice', () {
      var sends = 0;
      final plan = JitRequestPlan((_, _) => sends++);

      plan.addPubkeys('wss://relay.example.com', filter, [a.publicKey]);
      plan.flush();
      plan.addPubkeys('wss://relay.example.com', filter, [b.publicKey]);
      plan.flush();

      expect(sends, 1);
      expect(plan.isSent('wss://relay.example.com'), isTrue);
    });
  });
}
