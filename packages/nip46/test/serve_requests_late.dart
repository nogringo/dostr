import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';

/// Makes [relay] serve each REQ only after [delay], the way a REQ that the
/// client held back behind a full connection or an AUTH reaches it late.
void serveRequestsLate(MockRelay relay, Duration delay) {
  relay.onMessage = (client, message) {
    if (message[0] != 'REQ') return false;
    final id = message[1] as String;
    Timer(delay, () {
      client.subscriptions[id] = [
        for (final filter in message.skip(2))
          Filter.fromJson(filter as Map<String, dynamic>),
      ];
      client.send(['EOSE', id]);
    });
    return true;
  };
}
