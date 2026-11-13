---
label: Library Development
icon: repo-clone	

---


# Library development 🏗️

## Setup

Run `flutter pub get` at the root to install the dependencies of every package.

Run build runner (e.g. for generating mocks):\
`dart run build_runner build`

## Architecture

The repo is a monorepo of small packages, so that an app only depends on what it uses. `dostr_core` holds the relay connections, and the other packages build on it or stand on their own: the [package graph](package-graph.md) shows which depends on which.

Dostr uses Clean Architecture, for a clear separation of concerns that makes the code more accessible to new contributors. You can read more about it [here](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html). How a package lays out its folders is in [Contributing](CONTRIBUTING.md#project-structure).

An app keeps one `RelayManager` of `dostr_core` in memory: the state of the relays, and of the requests and publishes in flight, lives there.
