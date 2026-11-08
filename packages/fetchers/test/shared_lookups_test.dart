import 'dart:async';

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_fetchers/src/replaceable_lookup.dart';
import 'package:test/test.dart';

void main() {
  ReplaceableLookup finished(String _) => (
    versions: const Stream<Nip01Event>.empty(),
    result: Future.value(const EventNotFound()),
  );

  ReplaceableLookup running(String _) => (
    versions: StreamController<Nip01Event>().stream,
    result: Completer<EventLookup>().future,
  );

  test('drops the stale lookups as new ones start', () async {
    final lookups = SharedLookups(finished, reuseFor: Duration.zero);

    for (var i = 0; i < 1000; i++) {
      await lookups.lookup('p$i');
    }

    expect(lookups.length, lessThanOrEqualTo(64));
  });

  test('keeps the lookups still running', () async {
    var started = 0;
    final lookups = SharedLookups((pubKey) {
      started++;
      return pubKey.startsWith('running') ? running(pubKey) : finished(pubKey);
    }, reuseFor: Duration.zero);

    for (var i = 0; i < 100; i++) {
      lookups.watch('running$i').listen(null);
    }
    for (var i = 0; i < 1000; i++) {
      await lookups.lookup('done$i');
    }
    lookups.watch('running0').listen(null);

    expect(started, 1100);
    expect(lookups.length, lessThanOrEqualTo(200));
  });

  test('keeps a finished lookup while it is reused', () async {
    var started = 0;
    final lookups = SharedLookups((pubKey) {
      started++;
      return finished(pubKey);
    }, reuseFor: const Duration(minutes: 10));

    await lookups.lookup('p0');
    for (var i = 1; i < 1000; i++) {
      await lookups.lookup('p$i');
    }
    await lookups.lookup('p0');

    expect(started, 1000);
  });
}
