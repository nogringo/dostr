---
label: Common Terminology
order: 1
icon: bookmark

---

# Common terminology

| term | explanation | similar to |
| --- | --- | --- |
| **publish** | send an event to relays (NIP-01 EVENT) | broadcast, post |
| **query** | get data once and close the request, `closeOnEose: true` | get request |
| **subscription** | stream of events as they come in, `closeOnEose: false` | stream of data |
| **outbox relays** | the relays an account writes to, from its NIP-65 list | write relays |
| **inbox relays** | the relays an account reads from, from its NIP-65 list | read relays |
| **indexer relays** | relays asked for NIP-65 lists before the account's own relays are known, `defaultIndexerRelays` | bootstrap relays, seed relays |
| **UrlSet** | where something goes, described rather than listed, resolved later | relay set |
