import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_core/src/domain_layer/entities/relay_stats.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/relay_connection.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() async {
  test('stats', () async {
    RelayStats stats = MutableRelayStats();
    expect(0, stats.getTotalEventsRead());
    expect(0, stats.getTotalBytesRead());
  });

  test('counts the events read and hands out read-only maps', () {
    final stats = MutableRelayStats();
    final note = Nip01Event(pubKey: alice, kind: 1, tags: [], content: '');

    stats.incStatsByNewEvent(note, 100);
    stats.incStatsByNewEvent(note, 50);

    RelayStats view = stats;
    expect(view.eventsRead, {1: 2});
    expect(view.dataReadBytes, {1: 150});
    expect(view.getTotalEventsRead(), 2);
    expect(view.getTotalBytesRead(), 150);
    expect(() => view.eventsRead[1] = 0, throwsUnsupportedError);
    expect(() => view.dataReadBytes.clear(), throwsUnsupportedError);
  });
}
