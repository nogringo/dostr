import 'event_id.dart';
import 'nip_01_event.dart';

class Nip01Utils {
  /// checks if event id matches the event data (NIP-01)
  static bool isIdValid(Nip01Event event) => event.id == calculateId(event);

  static String calculateId(Nip01Event event) {
    return computeEventId(
      pubKey: event.pubKey,
      createdAt: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
    );
  }
}
