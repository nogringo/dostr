# Architecture decision records

These records preserve decisions and implementation context from earlier stages of the project. References to `ndk` may describe the former monolithic package rather than Dostr's current package structure.

- [Layered architecture](layered-architecture.md): the folder structure inside a package.
- [Relay authentication](relay-auth.md): who a query, subscription, broadcast or Blossom operation authenticates as.
- [Relay selection](relay-selection.md): use cases describe where they read and send, and the network engines go away.
- [REQ queue per connection](relay-req-queue.md): `dostr_core` holds back a REQ while its connection is full.
- [One live REQ per connection](relay-live-req.md): a subscription goes out alone, then listens through a REQ its connection shares.
