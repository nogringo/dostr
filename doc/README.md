# Dostr documentation

Each package documents itself in its README, shown on pub.dev and in [packages/](../packages/). The [package overview](../README.md#monorepo-packages) lists them. These pages cover what spans several packages.

- [Getting started](getting-started.md): install, query relays, sign and publish.
- [Outbox model](outbox-model.md): read where accounts write, publish where their readers look.
- [Tips](tips.md): one `RelayManager` per app, fewer redraws.
- [Performance](performance.md): how Dostr saves bandwidth and compute.
- [Common terminology](common-terminology.md): the words these pages use, and their other names.

Dostr does not ship ready to use feeds: you build them from the packages.

## Library development

- [Package graph](library-development/package-graph.md)
- [Architecture decision records](library-development/ADRs/README.md)
