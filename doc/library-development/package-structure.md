# Package structure

- `lib/<package>.dart` is the only library meant to be imported. It exports what
  the package offers.
- Every other file is under `lib/src/`, which other packages do not import (the
  `implementation_imports` lint).
- A package with several layers splits `lib/src/` into the folders below, as
  `dostr_core`, `dostr_blossom` and `dostr_nip59` do. A small package keeps its
  files flat in `lib/src/`.
- The internals of a use case sit in a folder named after it:
  `dostr_core/lib/src/domain_layer/usecases/relay_manager/` holds `RelayManager`
  and the parts it is made of.
- A package that needs a small helper another package keeps internal has its own
  copy rather than reaching into that package's `lib/src/`.

## Layers

- `config/`: defaults and constants.
- `shared/`: pure helpers on the entities, with no external dependency, by NIP
  where it applies (`shared/nips/nip01/`).
- `data_layer/`: what talks to the outside world. `repositories/` implements the
  contracts of `domain_layer/repositories/` (websocket, HTTP, files), `models/`
  converts JSON to entities.
- `domain_layer/`: `entities/` holds the data types, `repositories/` the
  contracts the use cases depend on, `usecases/` the logic.

A use case only knows contracts, so a websocket or HTTP client is swapped by
passing another implementation.
