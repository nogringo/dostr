import 'event_id.dart';
import 'nip_01_event.dart';

class Nip01Utils {
  @Deprecated('Use event.hasValidId')
  static bool isIdValid(Nip01Event event) => event.hasValidId;

  /// The id of the payload of [event], whatever id the event holds.
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
