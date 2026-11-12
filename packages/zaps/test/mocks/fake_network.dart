import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_zaps/dostr_zaps.dart';

/// Relays answering every query with all the events they hold, and keeping
/// subscriptions open until they are closed.
class FakeRelays {
  final List<Nip01Event> events = [];
  final List<({Filter filter, Duration timeout})> queries = [];
  final List<Filter> subscriptions = [];
  int closed = 0;

  final List<StreamController<Nip01Event>> _live = [];

  Stream<Nip01Event> query(Filter filter, {required Duration timeout}) async* {
    queries.add((filter: filter, timeout: timeout));
    for (final event in events) {
      yield event;
    }
  }

  ZapsSubscription subscribe(Filter filter) {
    subscriptions.add(filter);
    final controller = StreamController<Nip01Event>();
    _live.add(controller);
    return (
      events: controller.stream,
      close: () async {
        closed++;
        await controller.close();
      },
    );
  }

  void push(Nip01Event event) {
    for (final controller in _live) {
      if (!controller.isClosed) controller.add(event);
    }
  }
}
