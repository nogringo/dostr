import 'dart:convert';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_rust_verifier/dostr_rust_verifier.dart';

const _warmupIterations = 1000;
const _sampleIterations = 5000;
const _sampleCount = 9;

Future<void> main() async {
  final keyPair = Bip340.generateKeyPair();
  final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  const content = 'RustEventVerifier benchmark event';
  Nip01Event signed(Nip01Event event) =>
      Bip340.signEvent(event: event, privateKey: keyPair.privateKey);

  final event = signed(
    Nip01Event(
      pubkey: keyPair.publicKey,
      createdAt: createdAt,
      kind: 1,
      tags: const [],
      content: content,
    ),
  );
  final verifier = RustEventVerifier();
  const bip340Verifier = Bip340EventVerifier();

  final results = <Map<String, Object>>[
    await _benchmark(verifier, event, name: 'RustEventVerifier.verify'),
    // The baseline the README compares against, verified in Dart.
    await _benchmark(
      bip340Verifier,
      event,
      name: 'Bip340EventVerifier.verify',
      warmupIterations: 50,
      sampleIterations: 200,
    ),
  ];

  // Build and sign the larger fixture outside the timed verification loops.
  final largeTags = List.generate(
    200,
    (index) => ['x', '$index-${'a' * 1024}'],
  );
  final largeContent = 'b' * (64 * 1024);
  final largeEvent = signed(
    Nip01Event(
      pubkey: keyPair.publicKey,
      createdAt: createdAt,
      kind: 1,
      tags: largeTags,
      content: largeContent,
    ),
  );
  const largeDetails = '; 200 tags with 1 KiB values, 64 KiB content';
  results.addAll([
    await _benchmark(
      verifier,
      largeEvent,
      name: 'RustEventVerifier.verify.large_event',
      warmupIterations: 100,
      sampleIterations: 500,
      details: largeDetails,
    ),
    await _benchmark(
      bip340Verifier,
      largeEvent,
      name: 'Bip340EventVerifier.verify.large_event',
      warmupIterations: 20,
      sampleIterations: 100,
      details: largeDetails,
    ),
  ]);

  print(jsonEncode(results));
}

Future<Map<String, Object>> _benchmark(
  EventVerifier verifier,
  Nip01Event event, {
  required String name,
  int warmupIterations = _warmupIterations,
  int sampleIterations = _sampleIterations,
  String details = '',
}) async {
  // Nip01Event caches its payload id, so verifying the same instance again
  // would skip the hashing: each operation gets a fresh event, as from a relay.
  final json = event.toJson();
  List<Nip01Event> freshEvents(int count) =>
      List.generate(count, (_) => Nip01Event.fromJson(json));

  for (final fresh in freshEvents(warmupIterations)) {
    if (!await verifier.verify(fresh)) {
      throw StateError('$name warmup verification failed.');
    }
  }

  final samples = <double>[];
  for (var sample = 0; sample < _sampleCount; sample++) {
    final events = freshEvents(sampleIterations);
    final stopwatch = Stopwatch()..start();
    for (final fresh in events) {
      if (!await verifier.verify(fresh)) {
        throw StateError('$name verification failed.');
      }
    }
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds * 1000 / sampleIterations);
  }

  samples.sort();
  final medianNanosecondsPerOperation = samples[samples.length ~/ 2];
  return {
    'name': name,
    'unit': 'ns/op',
    'value': medianNanosecondsPerOperation,
    'range':
        '${samples.first.toStringAsFixed(0)}-${samples.last.toStringAsFixed(0)}',
    'extra':
        '$_sampleCount samples x $sampleIterations operations after '
        '$warmupIterations warmup operations$details',
  };
}
