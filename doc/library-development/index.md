---
label: Library Development
icon: repo-clone	

---


# Library development 🏗️

## Setup

Install [prerequisites](#setup)

run `melos bootstrap` to install all dependencies.

Run build runner: (e.g for generating mocks)\
`dart run build_runner build`

## Architecture

The repo is setup as a monorepo and packages are split to enable user choice of what to include.\
The main package is `ndk` which is the main entry point for the lib user. \
Other packages like `objectbox` or `ndk_flutter` are optional and can be included if needed.

NDK uses Clean Architecture. Reasons for it being clear separation of concerns and therefore making it more accessible for future contributors.\
You can read more about it [here](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html).

For initialization we use `presentation_layer/init.dart` to assemble all dependencies, these are then exposed in `presentation_layer/ndk.dart` the main entry point for the lib user.

The lib user is supposed to keep the [NDK] object in memory. \
The state of the relays, and of the requests and broadcasts in flight, lives in the `RelayManager` of `ndk_core`.

### Folder Structure of `ndk`

```bash
lib/
├── config/
│   └── # Configuration files
├── shared/
│   ├── nipX/ # NIP-specific code folders
│   └── # Internal code, no external dependencies
├── data_layer/
│   ├── data_sources/
│   │   └── # External APIs, WebSocket implementations, etc.
│   ├── models/
│   │   └── # Data transformation (e.g., JSON to entity)
│   └── repositories/
│       └── # Concrete repository implementations
├── domain_layer/
│   ├── entities/
│   │   └── # Core business objects
│   ├── repositories/
│   │   └── # Repository contracts
│   └── usecases/
│       └── # Business logic / use cases
├── presentation_layer/
│   └── # API design (exposing use cases to the outside world)
└── ndk.dart # Entry point, directs to presentation layer

```
