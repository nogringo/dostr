# dostr_event_store

An event store for Nostr clients: it keeps the events a client received by the rules a relay applies to what it stores, and reads them back with NIP-01 filters.

`EventStore` is the contract, and `MemoryEventStore` keeps the events for as long as the process lives, in pure Dart.
Another store, such as one on a database, implements `EventStore` and runs [`dostr_event_store_test_suite`](https://pub.dev/packages/dostr_event_store_test_suite) to keep the same rules, which [`package:dostr_event_store/rules.dart`](#another-store) gives as functions.

## Install

```yaml
dependencies:
  dostr_event_store: ^0.1.0
```

## Usage

```dart
import 'package:dostr_event_store/dostr_event_store.dart';

final store = MemoryEventStore();

await store.add(event);
final profiles = await store.query([
  Filter(authors: [pubkey], kinds: [0]),
]);
```

`add` tells what it did with the event through an `EventAddOutcome`: `stored`, or why it was not, `duplicate`, `ephemeral`, `expired`, `outdated` or `deleted`.
`addAll` adds a batch, such as the events a REQ brought, in their order as `add` one after the other, and gives the outcome of each in the same order: a store on a database can write them in one transaction.

`query` takes the filters of a REQ and gives the events that match at least one of them, newest first, and the lower id first at the same `created_at`, as NIP-01 orders them.
Each filter keeps its newest `limit` matches.
An empty list of filters matches nothing, and so does a filter with an empty list, such as `authors: []`.

`remove` removes what `query` gives for the same filters, and tells how many.
`close` releases the store, after which every other method throws a `StateError`.

The store does not verify events: add those whose id and signature were checked, as `dostr_core` checks what relays send.

## Relay rules

| NIP | Rule |
|-----|------|
| NIP-01 | An ephemeral event (20000 to 29999) is not stored. A replaceable event (0, 3, 10000 to 19999) replaces the version of the same kind and pubkey with an older `created_at`, and an addressable one (30000 to 39999) the version that also has the same `d` tag. At the same `created_at`, the lower id wins. |
| NIP-09 | A `kind:5` is stored, and removes the events its `e` tags name that its author wrote, and the versions of the addresses its `a` tags name, of its author, up to its `created_at`. While it is stored, those events are refused, so a copy from another relay does not bring them back. Once it is removed, they can be added again. A deletion request does not delete another one. |
| NIP-59 | The recipient of a gift wrap, the pubkey of its `p` tag, deletes it with a `kind:5` that names its id, as its author does. |
| NIP-40 | An event past its `expiration` is refused, and a stored one is no longer returned once it expires. An expired deletion request no longer refuses the events it targets. |

These rules read the time from `clock.now()` of [`package:clock`](https://pub.dev/packages/clock), so a test sets it with `withClock`.

## MemoryEventStore

`MemoryEventStore` indexes the events by id, author and kind, so a filter with `ids`, `authors` or `kinds` reads only the events it can match.
It drops an expired event when a query meets it.
It has no NIP-50 search: a filter with `search` matches nothing.

## Another store

`package:dostr_event_store/rules.dart` has the relay rules as the functions `MemoryEventStore` applies, so another store keeps them without coding them again:

| Function | Rule |
|----------|------|
| `newestFirst` | The NIP-01 order: newest first, then the lower id. |
| `replaces` | Whether a version replaces the stored one of its address. |
| `addressOf` | The `kind:pubkey:d` that the versions of a replaceable or addressable event share. |
| `deletedAddresses` | The addresses the `a` tags of a deletion request name, of its author, in the form of `addressOf`. |
| `canDelete` | Whether a deletion request deletes an event its `e` tags name: one of its author, or a gift wrap of its recipient. |
| `isExpired` | Whether an event has passed its NIP-40 `expiration`. |
