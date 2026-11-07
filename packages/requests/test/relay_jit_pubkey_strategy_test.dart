import 'dart:async';

import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_requests/src/jit_engine/jit_request_plan.dart';
import 'package:ndk_requests/src/jit_engine/relay_jit_pubkey_strategy.dart';
import 'package:test/test.dart';

void main() {
  KeyPair key1 = Bip340.generatePrivateKey();
  KeyPair key2 = Bip340.generatePrivateKey();
  KeyPair key3 = Bip340.generatePrivateKey();

  group('RelayJitPubkeyStrategy', () {
    test('starts relay candidate connections concurrently', () async {
      final delayedUrl = 'ws://delayed.example';
      final immediateUrl = 'ws://immediate.example';
      final delayedTransport = _ControlledTransport(open: false);
      final immediateTransport = _ControlledTransport(open: true);
      final factory = _ControlledTransportFactory({
        delayedUrl: delayedTransport,
        immediateUrl: immediateTransport,
      });
      addTearDown(() async {
        await delayedTransport.close();
        await immediateTransport.close();
      });

      final relayLists = [
        Nip65.fromMap(key1.publicKey, {delayedUrl: ReadWriteMarker.readWrite}),
        Nip65.fromMap(key2.publicKey, {delayedUrl: ReadWriteMarker.readWrite}),
        Nip65.fromMap(key3.publicKey, {
          immediateUrl: ReadWriteMarker.readWrite,
        }),
      ];
      final cacheManager = MemCacheManager();
      await cacheManager.saveUserRelayLists(
        relayLists.map(UserRelayList.fromNip65).toList(),
      );

      final relayManager = RelayManager(nostrTransportFactory: factory);
      final plan = JitRequestPlan((_, _) {});
      final candidates = await RelayJitPubkeyStrategy.plan(
        plan: plan,
        filter: Filter(
          authors: [key1.publicKey, key2.publicKey, key3.publicKey],
        ),
        connectedRelays: const [],
        bootstrapRelays: const [],
        cacheManager: cacheManager,
        desiredCoverage: 1,
        direction: ReadWriteMarker.writeOnly,
        ignoreRelays: const [],
      );
      final connecting = RelayJitPubkeyStrategy.connectCandidates(
        candidates: candidates,
        plan: plan,
        relayManager: relayManager,
        bootstrapRelays: const [],
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(factory.startedUrls, containsAll([delayedUrl, immediateUrl]));

      delayedTransport.open();
      await connecting;
    });

    test('blasts to bootstrap relays when relay-list cache throws', () async {
      final fallbackUrl = 'ws://fallback.example';
      final fallbackTransport = _ControlledTransport(open: true);
      final factory = _ControlledTransportFactory({
        fallbackUrl: fallbackTransport,
      });
      addTearDown(fallbackTransport.close);

      final relayManager = RelayManager(nostrTransportFactory: factory);
      final result = await relayManager.connectRelay(dirtyUrl: fallbackUrl);
      expect(result.connected, isTrue);

      final sent = <String, List<Filter>>{};
      final plan = JitRequestPlan((url, filters) => sent[url] = filters);
      final candidates = await RelayJitPubkeyStrategy.plan(
        plan: plan,
        filter: Filter(authors: [key1.publicKey]),
        connectedRelays: relayManager.connectedAnonymousRelays,
        bootstrapRelays: [fallbackUrl],
        cacheManager: _ThrowingUserRelayListCache(),
        desiredCoverage: 1,
        direction: ReadWriteMarker.writeOnly,
        ignoreRelays: const [],
      );
      plan.flush();

      expect(candidates, isEmpty);
      expect(sent.keys, [fallbackUrl]);
      expect(sent[fallbackUrl]!.single.authors, [key1.publicKey]);
    });
  });
}

class _ThrowingUserRelayListCache extends MemCacheManager {
  @override
  Future<UserRelayList?> loadUserRelayList(String pubKey) =>
      Future.error(StateError('cache unavailable'));
}

class _ControlledTransportFactory implements NostrTransportFactory {
  final Map<String, _ControlledTransport> transports;
  final List<String> startedUrls = [];

  _ControlledTransportFactory(this.transports);

  @override
  NostrTransport call(String url) {
    startedUrls.add(url);
    return transports[url]!;
  }
}

class _ControlledTransport implements NostrTransport {
  final StreamController<dynamic> _messages = StreamController.broadcast();
  final Completer<void> _ready = Completer<void>();
  final List<dynamic> sentData = [];
  bool _open;

  _ControlledTransport({required bool open}) : _open = open {
    ready = _ready.future;
    if (open) {
      _ready.complete();
    }
  }

  void open() {
    _open = true;
    if (!_ready.isCompleted) {
      _ready.complete();
    }
  }

  @override
  late Future<void> ready;

  @override
  Future<void> close() async {
    _open = false;
    if (!_ready.isCompleted) {
      _ready.complete();
    }
    if (!_messages.isClosed) {
      await _messages.close();
    }
  }

  @override
  int? closeCode() => null;

  @override
  String? closeReason() => null;

  @override
  bool isConnecting() => !_open;

  @override
  bool isOpen() => _open;

  @override
  StreamSubscription listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) => _messages.stream.listen(onData, onError: onError, onDone: onDone);

  @override
  void send(dynamic data) => sentData.add(data);
}
