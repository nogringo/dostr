import 'dart:async';

import 'package:ndk/ndk.dart';
import 'package:ndk_core/domain_layer/entities/relay_connectivity.dart';
import 'package:ndk_core/domain_layer/repositories/nostr_transport.dart';
import 'package:test/test.dart';

class _Transport implements NostrTransport {
  bool closed = false;
  final controller = StreamController<dynamic>();

  @override
  Future<void> ready = Future.value();
  @override
  bool isOpen() => !closed;
  @override
  bool isConnecting() => false;
  @override
  Future<void> close() async => closed = true;
  @override
  void send(dynamic data) {}
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) => controller.stream.listen(onData, onError: onError, onDone: onDone);
  @override
  int? closeCode() => null;
  @override
  String? closeReason() => null;
}

void main() {
  test(
    'NDK background hook closes idle relay and runs lifecycle hooks',
    () async {
      final anonymous = RelayConnectionKey.anonymous('wss://relay.example');
      final ndk = Ndk.emptyBootstrapRelaysConfig();
      final backgrounded = <bool>[];
      var destroyed = false;
      ndk.addLifecycleHooks(
        onBackgrounded: (value) async => backgrounded.add(value),
        onDestroy: () async => destroyed = true,
      );
      final transport = _Transport();
      ndk.relays.globalState.relays[anonymous] = RelayConnectivity(
        key: anonymous,
        relay: Relay(url: anonymous.url),
        relayTransport: transport,
      );
      await ndk.setBackgrounded(true);
      expect(transport.closed, isTrue);
      expect(ndk.relays.globalState.relays, isEmpty);
      await ndk.setBackgrounded(false);
      expect(backgrounded, [true, false]);
      await ndk.destroy();
      expect(destroyed, isTrue);
    },
  );
}
