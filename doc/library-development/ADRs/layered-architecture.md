# Architecture Decision Record: Layered Architecture

Title: Layered Architecture - folder structure

## status

Accepted

Updated on 26-06-2024, amended on 14-11-2026 for the Dostr packages

## contributors

- Main contributor(s): leo-lox

- Reviewer(s): frnandu

- final decision made by: frnandu, leo-lox

## In the Dostr packages

The proposal below was written for the monolithic `ndk` package. Each Dostr
package applies it this way:

- `lib/<package>.dart` is the only library meant to be imported. It exports
  what the package offers and plays the role of `presentation_layer/`.
- Every other file is under `lib/src/`, which other packages do not import
  (the `implementation_imports` lint).
- A package with several layers keeps the folders of the proposal inside
  `lib/src/` (`config/`, `data_layer/`, `domain_layer/`, `shared/`), as
  `dostr_core`, `dostr_blossom` and `dostr_nip59` do. A small package keeps its
  files flat in `lib/src/`.
- The internals of a use case sit in a folder named after it:
  `dostr_core/lib/src/domain_layer/usecases/relay_manager/` holds
  `RelayManager` and the parts it is made of.
- A package that needs a small helper another package keeps internal has its
  own copy rather than reaching into that package's `lib/src/`.

## Context and Problem Statement

Right now files and folders follow a simple nip folder structure (each nip gets a folder). There are no clear guidelines on where to put stuff and how to attach other packages.

## Main Proposal

Implement a clear folder structure and a layered architecture that makes it easy to include third-party packages.

The proposed structure looks like this:

`project-root/`

- `lib/`
  - `config/`
    - `# contains configuration files`
  - `shared/`
    - `nipX # folders for nip specific code`
    - `# only internal code, no external dependencies!`
  - `data_layer/`
    - `data_sources/`
      - `# external apis, websocket impl etc.`
    - `models/`
      - `# type conversion e.g. json to entity`
    - `repositories/`
      - `# repository implementations (implementing domain_layer repos)`
  - `domain_layer/`
    - `entities/`
      - `# our entities e.g. data types`
    - `repositories/`
      - `# contracts`
    - `usecases/`
      - `# our main code / business logic`
  - `presentation_layer/`
    - `# contains our api design (makes usecases accessible to outside world)`
  - `lib.dart # entrypoint, points to presentation_layer`
- `tests/`
  - `usecases/`
    - `# integration_tests`
  - `unit/`
    - `# unit tests`

The shared folder is there to make the transition easier. Ideally, shared schuld only contain business logic and therefore extend the use cases folder. It can also be used for pure functions that use our entities.

## Consequences

in terms of difficulty, impact on other teams or the whole codebase, time, budget, uncertainty, etc

- Pros
  - It makes it easy to include third-party packages without breaking stuff in the future.
  - Clear separation of concerns. It makes it easier for other developers to contribute.
  - We can easily switch out different third-party components. (e.g. websocket)
  - Makes clear what is accessible to the user and what is not.
  - Easy to integrate bridge structure like a rust bridge.

- Cons
  - Requires a lot of rearranging the code base.
  - Guidelines need to be enforced.

If we want to transition to a event driven architecture this could be possible by injecting a message bus into our usecases

## Alternative proposals

none so far

## Final Notes

Proposal Accepted.
Going forward after merging of 
https://github.com/nogringo/dostr/tree/relay_jit_ranking
https://github.com/nogringo/dostr/tree/split-relay-manager
https://github.com/nogringo/dostr
completed 
