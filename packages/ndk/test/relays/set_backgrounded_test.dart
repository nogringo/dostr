import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

void main() {
  test(
    'NDK background hook closes idle relay and runs lifecycle hooks',
    () async {
      final relay = MockRelay(name: "idle relay");
      await relay.start();
      addTearDown(relay.stop);
      final ndk = Ndk.emptyBootstrapRelaysConfig();
      final backgrounded = <bool>[];
      var destroyed = false;
      ndk.addLifecycleHooks(
        onBackgrounded: (value) async => backgrounded.add(value),
        onDestroy: () async => destroyed = true,
      );
      await ndk.relays.connectRelay(dirtyUrl: relay.url);
      expect(relay.openClients.length, 1);

      await ndk.setBackgrounded(true);
      expect(ndk.relays.connectivities, isEmpty);
      for (var i = 0; i < 50 && relay.openClients.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(relay.openClients.length, 0);

      await ndk.setBackgrounded(false);
      expect(backgrounded, [true, false]);
      await ndk.destroy();
      expect(destroyed, isTrue);
    },
  );
}
