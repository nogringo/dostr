import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import '../mocks/mock_relay.dart';

void main() {
  test(
    'NDK background hook closes idle relay and runs lifecycle hooks',
    () async {
      final relay = MockRelay(name: "idle relay", signEvents: false);
      await relay.startServer();
      addTearDown(relay.stopServer);
      final ndk = Ndk.emptyBootstrapRelaysConfig();
      final backgrounded = <bool>[];
      var destroyed = false;
      ndk.addLifecycleHooks(
        onBackgrounded: (value) async => backgrounded.add(value),
        onDestroy: () async => destroyed = true,
      );
      await ndk.relays.connectRelay(dirtyUrl: relay.url);
      expect(relay.connectedClientCount, 1);

      await ndk.setBackgrounded(true);
      expect(ndk.relays.connectivities, isEmpty);
      for (var i = 0; i < 50 && relay.connectedClientCount > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(relay.connectedClientCount, 0);

      await ndk.setBackgrounded(false);
      expect(backgrounded, [true, false]);
      await ndk.destroy();
      expect(destroyed, isTrue);
    },
  );
}
