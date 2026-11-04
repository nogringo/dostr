import 'dart:math';

import 'package:ndk/config/broadcast_defaults.dart';
import '../../../repositories/cache_manager.dart';
import '../../user_relay_lists/user_relay_lists.dart';

/// broadcast to other read relays
class RelayJitBroadcastOtherReadStrategy {
  /// The nip65 inbox (read) relays of [pubkeysOfInbox], at most
  /// [BroadcastDefaults.MAX_INBOX_RELAYS_TO_BROADCAST] for each of them.
  static Future<List<String>> relays({
    required CacheManager cacheManager,
    required List<String> pubkeysOfInbox,
  }) async {
    final nip65Data = await UserRelayLists.getUserRelayListCacheLatest(
      pubkeys: pubkeysOfInbox,
      cacheManager: cacheManager,
    );

    List<String> myWriteRelayUrls = [];

    /// filter read relays
    for (final userNip65 in nip65Data) {
      final completeList = userNip65.relays.entries
          .where((element) => element.value.isRead)
          .map((e) => e.key)
          .toList();

      // cut list of at a certain threshold
      final maxList = completeList.sublist(
        0,
        min(
          completeList.length,
          BroadcastDefaults.MAX_INBOX_RELAYS_TO_BROADCAST,
        ),
      );
      myWriteRelayUrls.addAll(maxList);
    }
    return myWriteRelayUrls;
  }
}
