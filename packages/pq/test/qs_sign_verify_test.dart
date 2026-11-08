import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_pq/ndk_pq.dart';
import 'package:test/test.dart';

import '../../ndk/test/tools/simple_profiler.dart';

void main() async {
  group("qs_sign + qs_verify", skip: true, () {
    test('dev - test', () async {
      final profiler = SimpleProfiler('QS Sign + Verify');

      final level = 2;

      final myKeyPair = QsRustEventSigner.generateKeypair(level: level);

      final eventVerifier = QsRustEventVerifier(level: level);
      final signer = QsRustEventSigner(level: level, keypair: myKeyPair);

      final usignedEvent = Nip01Event(
        content: "hello",
        kind: 1,
        pubKey: '',
        tags: [],
      );

      profiler.checkpoint('Created unsigned event');
      final signedEvent = await signer.sign(usignedEvent);

      profiler.checkpoint('Event signed with QS signature');
      final isValid = await eventVerifier.verify(signedEvent);

      profiler.checkpoint('QS sign + verify completed, valid: $isValid');

      expect(isValid, true);

      print("\n\nLevel: $level\n");
      print("Signature: ${signedEvent.sig}\n");
      print("Event ID: ${signedEvent.id}\n");
      print("Public Key: ${signedEvent.pubKey}\n\n");
    });

    test('dev - bulk speed test', () async {
      final profiler = SimpleProfiler('QS Bulk Sign + Verify');

      final level = 5;
      final messageCount = 1000; // Configurable via variable

      final myKeyPair = QsRustEventSigner.generateKeypair(level: level);

      final eventVerifier = QsRustEventVerifier(level: level);
      final signer = QsRustEventSigner(level: level, keypair: myKeyPair);

      profiler.checkpoint('Started bulk test with $messageCount messages');

      // Create all unsigned events first
      final unsignedEvents = List.generate(
        messageCount,
        (index) => Nip01Event(
          content: "hello message $index",
          kind: 1,
          pubKey: '',
          tags: [],
        ),
      );

      profiler.checkpoint('Created $messageCount unsigned events');

      // Sign all events in parallel
      final signedEvents = await Future.wait(
        unsignedEvents.map((event) => signer.sign(event)),
      );

      profiler.checkpoint('Signed $messageCount events');

      // Verify all events in parallel
      final isValidations = await Future.wait(
        signedEvents.map((signedEvent) => eventVerifier.verify(signedEvent)),
      );

      profiler.checkpoint('Verified $messageCount events');

      // Check if all verifications passed
      bool allValid = isValidations.every((valid) => valid);
      int failedCount = isValidations.where((valid) => !valid).length;

      final checkpointString =
          'QS sign + verify completed: $messageCount total, $failedCount failed';
      profiler.checkpoint(checkpointString);

      expect(allValid, true);

      profiler.end();

      print("Events processed: $messageCount");
      print("Verification failures: $failedCount");
      print("Used Level: $level\n\n");
    });
  });
}
