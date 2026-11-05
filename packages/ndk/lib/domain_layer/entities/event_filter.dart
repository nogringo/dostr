import 'package:ndk_nip01/ndk_nip01.dart';

/// A class that filters events \
/// Used to clean event streams based on the event
abstract class EventFilter {
  /// Filters an event \
  /// true => event is accepted \
  /// false => event is rejected
  bool filter(Nip01Event event);
}
