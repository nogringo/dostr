import 'package:dostr_nip01/dostr_nip01.dart';

/// What [EventStore.add] did with an event.
enum EventAddOutcome {
  /// The event is stored. It replaced the older version of its replaceable
  /// or addressable event, and, as a deletion request, removed the events it
  /// targets.
  stored,

  /// An event with the same id is already stored.
  duplicate,

  /// Its kind is ephemeral (20000 to 29999), which relays do not store.
  ephemeral,

  /// Its NIP-40 `expiration` has passed.
  expired,

  /// A newer version of its replaceable or addressable event is stored.
  outdated,

  /// A stored NIP-09 deletion request targets it.
  deleted,
}

/// Where a client keeps the events it received, by the rules a relay applies
/// to what it stores, to read them back by filter.
///
/// - NIP-01: an ephemeral event is not stored. A replaceable event replaces
///   the version of the same kind and pubkey with an older `created_at`, and
///   an addressable one the version that also has the same `d` tag. At the
///   same `created_at`, the lower id wins.
/// - NIP-09: a `kind:5` is stored, and removes the events its `e` tags name
///   that its author wrote, and the versions of the addresses its `a` tags
///   name, of its author, up to its `created_at`. While it is stored, those
///   events are refused. A deletion request does not delete another one.
/// - NIP-59: the recipient of a gift wrap, the pubkey of its `p` tag, deletes
///   it with a `kind:5` that names its id, as its author does.
/// - NIP-40: an event past its `expiration` is refused, and a stored one is
///   no longer returned once it expires. An expired deletion request no longer
///   refuses the events it targets. The store may drop an expired event.
///
/// The store does not verify events: add those whose id and signature were
/// checked, as dostr_core checks what relays send.
///
/// The current time is `clock.now()` of package:clock, read when a method is
/// called, so a test sets it with `withClock`.
///
/// Once [close] was called, every other method throws a [StateError].
abstract interface class EventStore {
  /// Adds [event] by the rules above, and tells what it did.
  Future<EventAddOutcome> add(Nip01Event event);

  /// Adds [events] in their order, as [add] one after the other, and tells
  /// what it did with each, in the same order.
  ///
  /// It adds a batch, such as the events a REQ brought: a store on a database
  /// can write them in one transaction.
  Future<List<EventAddOutcome>> addAll(List<Nip01Event> events);

  /// The stored events that match at least one of [filters], newest first,
  /// and the lower id first at the same `created_at`, as NIP-01 orders them.
  ///
  /// Each filter keeps its newest `limit` matches. A filter with a NIP-50
  /// `search` matches what the store finds for it, or nothing in a store
  /// without search, such as [MemoryEventStore]. An empty [filters] matches
  /// nothing.
  Future<List<Nip01Event>> query(List<Filter> filters);

  /// Removes the events [query] gives for [filters], and tells how many.
  ///
  /// The events a removed deletion request targeted can be added again.
  Future<int> remove(List<Filter> filters);

  /// Releases what the store holds. Closing it again does nothing.
  Future<void> close();
}
