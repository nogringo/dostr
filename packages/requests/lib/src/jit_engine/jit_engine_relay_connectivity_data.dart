import 'package:ndk_core/domain_layer/entities/relay_connectivity.dart';

import 'package:ndk_cache/ndk_cache.dart';

/// additional data for the JIT engine
class JitEngineRelayConnectivityData {
  List<RelayJitAssignedPubkey> assignedPubkeys = [];

  /// adds pubkeys with a direction to assigned Pubkeys
  void addPubkeysToAssignedPubkeys(
    List<String> pubkeys,
    ReadWriteMarker direction,
  ) {
    for (var pubkey in pubkeys) {
      assignedPubkeys.add(RelayJitAssignedPubkey(pubkey, direction));
    }
  }
}

/// Represents a relay jit assigned pubkey
class RelayJitAssignedPubkey {
  /// hex pubkey
  final String pubkey;

  /// direction the assignment
  final ReadWriteMarker direction;

  /// Creates a new relay jit assigned pubkey
  RelayJitAssignedPubkey(this.pubkey, this.direction);
}

final _jitEngineData = Expando<JitEngineRelayConnectivityData>();

extension JitEngineRelayConnectivity on RelayConnectivity {
  /// the JIT engine data of this connection, gone with the connection
  JitEngineRelayConnectivityData get jitEngineData =>
      _jitEngineData[this] ??= JitEngineRelayConnectivityData();
}
