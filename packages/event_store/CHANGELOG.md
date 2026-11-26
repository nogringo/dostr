## 0.1.0

 - Initial release: the `EventStore` contract, which keeps events by the NIP-01, NIP-09, NIP-59 and NIP-40 rules of a relay and reads them back by filter, with `EventAddOutcome`, and `MemoryEventStore`, which keeps them in memory.
 - `addAll` adds a batch of events in their order, such as those a REQ brought, and gives the `EventAddOutcome` of each.
 - `package:dostr_event_store/rules.dart` has these rules as functions, for another store to apply them as `MemoryEventStore` does.
