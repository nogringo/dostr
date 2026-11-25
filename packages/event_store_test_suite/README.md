# dostr_event_store_test_suite

A shared test suite for implementations of the `EventStore` of [`dostr_event_store`](https://pub.dev/packages/dostr_event_store).
Every store runs the same cases, so they all keep the relay rules that `EventStore` documents.

`MemoryEventStore` runs it, and so can any other store, such as one on a database.

## Usage

Add `dostr_event_store_test_suite` as a **dev dependency**:

```yaml
dev_dependencies:
  dostr_event_store_test_suite: ^0.1.0
```

Then in your test file:

```dart
import 'package:dostr_event_store_test_suite/dostr_event_store_test_suite.dart';

void main() {
  runEventStoreTestSuite(
    name: 'MyEventStore',
    createStore: () => MyEventStore.open(...),
  );
}
```

`createStore` returns an empty store for each test, which the suite closes once the test ends.
The suite sets the time with `withClock` of [`package:clock`](https://pub.dev/packages/clock), so the store reads it with `clock.now()` when a method is called.
It does not test NIP-50 search, which each store reads its own way.

## What's tested

| Group | What it verifies |
|-------|-----------------|
| **add** | Gives back an event as it was added, tags, content and sig included; tells a duplicate; does not store an ephemeral event |
| **query** | Matches `ids`, `authors`, `kinds` and tag filters; bounds `created_at` with `since` and `until`, both included; gives the matches of every filter once, newest first, and the lower id first at the same `created_at`; keeps the newest `limit` matches of each filter; an empty filter matches every event, and no filter, an empty list or a `limit` of 0 match nothing |
| **NIP-01 replaceable events** | A newer version replaces the older one and an older one is outdated, the lower id wins at the same `created_at`, for kinds 0, 3 and 10000 to 19999, and per `d` tag for addressable kinds, where a missing `d` tag reads as an empty one; each author has its own version; regular events are all kept |
| **NIP-09 deletion requests** | Remove the events their `e` tags name, of their author only, and refuse them afterwards, even those that come later; remove the versions of an address of their author up to their `created_at`, and refuse those versions; do not delete another deletion request; once removed, let the events they named in again |
| **NIP-59 gift wraps** | Their recipient deletes them, before or after they arrive, and so does their author; another pubkey cannot, nor can the pubkey a note refers to |
| **NIP-40 expiration** | Refuses an event from its expiration on, stops giving a stored event once it expires, keeps an event whose expiration is not a number; an expired deletion request no longer refuses what it named, and an expired version gives way to an older one |
| **remove** | Removes what `query` gives and tells how many, keeps to the `limit` of each filter, lets an older version in once the newer one is gone |
| **close** | Every other method throws a `StateError`, and closing again completes |
