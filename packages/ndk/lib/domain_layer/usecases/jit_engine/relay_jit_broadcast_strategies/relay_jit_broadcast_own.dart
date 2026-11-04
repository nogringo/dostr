import '../../../../shared/logger/logger.dart';
import '../../../entities/nip_01_event.dart';
import '../../../repositories/cache_manager.dart';
import '../../user_relay_lists/user_relay_lists.dart';

/// broadcast to own outbox relays
class RelayJitBroadcastOutboxStrategy {
  /// The nip65 outbox (write) relays of the author of [eventToPublish], or
  /// [bootstrapRelays] when there is no nip65 data for them.
  static Future<List<String>> relays({
    required Nip01Event eventToPublish,
    required CacheManager cacheManager,
    required List<String> bootstrapRelays,
  }) async {
    final nip65Data = await UserRelayLists.getUserRelayListCacheLatestSingle(
      pubkey: eventToPublish.pubKey,
      cacheManager: cacheManager,
    );

    if (nip65Data == null) {
      Logger.log.w(
        () =>
            "broadcast - could not find nip65 data for ${eventToPublish.pubKey}, using DEFAULT_BOOTSTRAP_RELAYS for now. \nPlease ensure nip65Data exists to use outbox model => UserRelayLists usecase",
      );
      return bootstrapRelays;
    }

    /// get all relays where write marker is write
    return nip65Data.relays.entries
        .where((element) => element.value.isWrite)
        .map((e) => e.key)
        .toList();
  }
}
