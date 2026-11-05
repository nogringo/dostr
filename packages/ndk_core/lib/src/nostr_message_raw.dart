import '../domain_layer/entities/nip_01_event.dart';

enum NostrMessageRawType {
  notice,
  event,
  eose,
  ok,
  closed,
  auth,

  /// well formed, of a type `RelayManager` leaves to its protocol handlers
  unknown,

  /// not JSON, or a known type with a missing or mistyped field
  invalid,
}

class NostrMessageRaw {
  final NostrMessageRawType type;
  final Nip01Event? nip01Event;
  final String? requestId;
  final dynamic otherData;

  NostrMessageRaw({
    required this.type,
    this.nip01Event,
    this.requestId,
    this.otherData,
  });
}
