---
label: Publishing
icon: rocket
order: 100
---

# Publishing

Packages are published by hand with `dart pub publish`. Each package has its own version, and a package is released only when it changed since its last release.

## Choose the version

List what changed in a package since its last stable release:

```sh
git log dostr_nip01-v0.1.0..HEAD -- packages/nip01
```

The largest change since that **stable** release sets the version, not the changes since the last prerelease:

| Change | Below 1.0.0 | From 1.0.0 |
| --- | --- | --- |
| Breaking | `0.4.2` → `0.5.0` | `1.4.2` → `2.0.0` |
| New feature | `0.4.2` → `0.4.3` | `1.4.2` → `1.5.0` |
| Fix | `0.4.2` → `0.4.3` | `1.4.2` → `1.4.3` |

A prerelease appends `-dev.N` to the version it leads to: `0.5.0-dev.0`, then `0.5.0-dev.1`. When a breaking change lands during a `0.4.3-dev.N` series, the next prerelease is `0.5.0-dev.0`. Releasing that series as `0.4.3` would ship the breaking change to every app on `^0.4.2`.

A package that re-exports another one (`export 'package:dostr_...'` in its `lib/`) breaks when that package breaks: a breaking change in `dostr_nip01` is a breaking change in `dostr_core`.

A package that depends on a released package needs a release of its own only when its constraint no longer accepts the new version, or when it re-exports the package. Otherwise leave it as it is.

## Prepare the release

For each package to release:

1. Set `version` in its `pubspec.yaml`.
2. Add a `## <version>` section at the top of its `CHANGELOG.md`.
3. Update the constraint of each workspace package that depends on it, where the constraint no longer accepts the new version.

For `dostr_core`, also set `packageVersion` in `packages/core/lib/src/version.dart`.

Run `flutter pub get` at the root, then commit. Publish from that commit, so the tags point at the published source.

## Publish

Publish a package after the packages it depends on: the [package graph](package-graph.md) sorts them by layer, and layer 0 goes first. In each package directory:

```sh
dart pub publish --dry-run
dart pub publish
```

Then tag each published package and push its tag. The tag is where the next release starts listing changes:

```sh
git tag dostr_nip01-v0.2.0
git push origin dostr_nip01-v0.2.0
```

## Release dostr_core

Once `dostr_core` is on pub.dev, tag the same commit `v<version>` and push the tag:

```sh
git tag v0.11.0
git push origin v0.11.0
```

That tag runs two workflows:

- `release.yml` creates the GitHub release from the `## 0.11.0` section of `packages/core/CHANGELOG.md`, and marks it as a prerelease when the version contains `-dev`.
- `deploy-docs.yml` deploys the documentation with that version as its label. It skips prerelease tags.

Push `v<version>` only after the publication succeeded.
