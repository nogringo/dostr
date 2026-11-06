import 'package:ndk_nip01/ndk_nip01.dart';

import 'delivery_records.dart';

/// Where [PendingBroadcastDelivery] keeps its delivery state, next to the
/// events it delivers. NDK's `CacheManager` implements it.
abstract interface class DeliveryStore {
  Future<Nip01Event?> loadEvent(String id);

  Future<void> saveEvent(Nip01Event event);

  /// Removes the event along with its delivery record and relay targets.
  Future<void> removeEvent(String id);

  /// Visible events only: of a replaceable or addressable event, just the
  /// version that supersedes the others.
  Future<List<Nip01Event>> loadEvents({
    List<String>? pubKeys,
    List<int>? kinds,
    Map<String, List<String>>? tags,
    int? limit,
  });

  /// Persist aggregate delivery state for one event.
  Future<void> saveEventDeliveryRecord(EventDeliveryRecord record);
  Future<void> saveEventDeliveryRecords(List<EventDeliveryRecord> records);
  Future<EventDeliveryRecord?> loadEventDeliveryRecord(String eventId);
  Future<List<EventDeliveryRecord>> loadEventDeliveryRecords({
    EventDeliveryStatus? status,
    int? limit,
  });
  Future<void> removeEventDeliveryRecord(String eventId);
  Future<void> removeAllEventDeliveryRecords();

  /// Persist one relay-specific delivery target.
  Future<void> saveRelayDeliveryTarget(RelayDeliveryTarget target);
  Future<void> saveRelayDeliveryTargets(List<RelayDeliveryTarget> targets);
  Future<RelayDeliveryTarget?> loadRelayDeliveryTarget({
    required String eventId,
    required String relayUrl,
  });
  Future<List<RelayDeliveryTarget>> loadRelayDeliveryTargets({
    String? eventId,
    String? relayUrl,
    RelayDeliveryState? state,
    bool excludeAcked = false,
    int? limit,
  });
  Future<void> removeRelayDeliveryTarget({
    required String eventId,
    required String relayUrl,
  });
  Future<void> removeRelayDeliveryTargets(String eventId);
  Future<void> removeAllRelayDeliveryTargets();
}
