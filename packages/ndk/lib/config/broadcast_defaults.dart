// ignore_for_file: constant_identifier_names

import 'package:ndk_broadcast/ndk_broadcast.dart'
    show kMaxInboxRelaysToBroadcast;
import 'package:ndk_core/config/broadcast_defaults.dart' as core;

/// defaults
class BroadcastDefaults {
  /// the max amout of inbox relays to push a event per pubkey
  static const int MAX_INBOX_RELAYS_TO_BROADCAST = kMaxInboxRelaysToBroadcast;
  static const double CONSIDER_DONE_PERCENT =
      core.BroadcastDefaults.CONSIDER_DONE_PERCENT;
  static const Duration TIMEOUT = core.BroadcastDefaults.TIMEOUT;
  static const bool SAVE_TO_CACHE = true;
}
