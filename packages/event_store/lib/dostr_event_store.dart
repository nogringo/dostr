/// The [EventStore] contract, which keeps Nostr events by the rules of a
/// relay and reads them back by filter, and [MemoryEventStore], which keeps
/// them for as long as the process lives.
///
/// `package:dostr_event_store/rules.dart` has these rules as functions, for
/// another store.
library;

export 'src/event_store.dart';
export 'src/memory_event_store.dart';
