import 'dart:async';

import 'package:dostr_core/domain_layer/usecases/requests/verified_event_cache.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

class _GatedVerifier implements EventVerifier {
  final gate = Completer<bool>();
  int calls = 0;

  @override
  Future<bool> verify(Nip01Event event) {
    calls++;
    return gate.future;
  }
}

void main() {
  test('runs one verification for concurrent checks of a pair', () async {
    final cache = VerifiedEventMemCache();
    final verifier = _GatedVerifier();
    final event = signedEvent(createdAt: 1);

    final first = cache.verifyOnce(event, verifier);
    final second = cache.verifyOnce(event, verifier);
    verifier.gate.complete(true);

    expect(await Future.wait([first, second]), [true, true]);
    expect(verifier.calls, 1);
    expect(cache.hasVerifiedSignature(event.id, event.sig), isTrue);
  });

  test('only vouches for the signature it checked', () async {
    final cache = VerifiedEventMemCache();
    final event = signedEvent(createdAt: 1);

    await cache.verifyOnce(event, FakeVerifier());

    expect(cache.hasVerifiedSignature(event.id, 'e' * 128), isFalse);
  });

  test('does not remember a failed verification', () async {
    final cache = VerifiedEventMemCache();
    final forged = signedEvent(createdAt: 1).copyWith(sig: 'e' * 128);

    expect(await cache.verifyOnce(forged, FakeVerifier()), isFalse);
    expect(cache.hasVerifiedSignature(forged.id, forged.sig), isFalse);
  });

  test('evicts the least recently used pair', () {
    final cache = VerifiedEventMemCache(maxSize: 2)
      ..markVerified('a', 'sig')
      ..markVerified('b', 'sig');

    expect(cache.hasVerifiedSignature('a', 'sig'), isTrue);
    cache.markVerified('c', 'sig');

    expect(cache.hasVerifiedSignature('a', 'sig'), isTrue);
    expect(cache.hasVerifiedSignature('b', 'sig'), isFalse);
    expect(cache.hasVerifiedSignature('c', 'sig'), isTrue);
  });

  test('a verification started before clear cannot repopulate it', () async {
    final cache = VerifiedEventMemCache();
    final verifier = _GatedVerifier();
    final event = signedEvent(createdAt: 1);

    final pending = cache.verifyOnce(event, verifier);
    cache.clear();
    verifier.gate.complete(true);

    expect(await pending, isTrue);
    expect(cache.hasVerifiedSignature(event.id, event.sig), isFalse);
  });
}
