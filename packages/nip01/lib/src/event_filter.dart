import 'nip_01_event.dart';

/// A filter that drops events from a stream before they reach the caller.
abstract class EventFilter {
  /// Whether to keep [event]: false drops it.
  bool filter(Nip01Event event);
}
