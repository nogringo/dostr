import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_metadatas/ndk_metadatas.dart';
import 'package:ndk_requests/ndk_requests.dart';
import 'package:ndk_requests/src/jit_engine/jit_request_plan.dart';
import 'package:test/test.dart';

/// A second REQ with the same id replaces the first on the relay (NIP-01), so
/// whatever an engine routes to one relay has to travel in a single REQ.
void main() {
  final a = Bip340.generatePrivateKey();
  final b = Bip340.generatePrivateKey();

  test('a relay set relay gets every filter that maps to it', () async {
    const url = 'wss://relay.example.com';
    final engine = RelaySetsEngine(bootstrapRelays: []);
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
        Filter(kinds: [Nip01Event.kTextNoteKind], authors: [a.publicKey]),
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
      [Nip01Event.kTextNoteKind],
      [Metadata.kKind],
    ]);
  });

  group('JitRequestPlan', () {
    final filter = Filter(
      kinds: [Nip01Event.kTextNoteKind],
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
