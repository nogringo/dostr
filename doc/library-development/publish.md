---
label: Publishing
icon: rocket
order: 100
---

# Publishing

## Full release order

Complete releases have two distinct stages, in this order:

1. Prepare and merge the package release PR. Automation creates a
   package-scoped tag such as `dostr_core-v0.11.0`, which pub.dev uses to
   authenticate the publication workflow, and then publishes the package.
2. After `dostr_core` publication succeeds, automation also creates the plain
   release tag, such as `v0.11.0`, and dispatches the tag-based release and
   documentation workflows. For other packages, the package-scoped tag is the
   release tag.

## 1. Publish packages to pub.dev

Open the [Prepare package release workflow](https://github.com/relaystr/ndk/actions/workflows/prerelease-manual.yaml),
select **Run workflow**, and choose one release mode:

| Release mode | Result |
| --- | --- |
| `stable` | Calculates the next stable versions from conventional commits. |
| `development-prerelease` | Calculates the next development versions, such as `0.11.0-dev.3`. This mode is also run automatically after ordinary PRs merge. |
| `graduate-prerelease` | Removes the prerelease suffix without changing its base version; for example, `0.11.0-dev.3` becomes `0.11.0`. |
| `exact` | Sets one selected package to the exact version entered. Melos also updates affected workspace dependents and creates a changelog stub to review. |

The `exact_package` and `exact_version` inputs are used only with `exact` mode.
For the other modes, leave them at their defaults.

### Release dostr_core 0.11.0 as a stable version

Run the workflow with:

- `release_mode`: `exact`
- `exact_package`: `dostr_core`
- `exact_version`: `0.11.0`

The workflow opens a versioned PR named
`chore(release): publish dostr_core 0.11.0`. Development versions instead use
`chore(prerelease)`. The title lists every publishable package whose version
changed. Replace the generated `Stable release.` changelog stub with the actual
release notes, then review the generated dependent-package constraint updates
before merging the PR.

Merging that release PR creates package-scoped authentication tags and
publishes every changed, publishable package to pub.dev. Each publication
workflow must run from its package tag because pub.dev's trusted publisher is
configured to accept tag identities. Preparing the PR performs only a publish
dry run; it does not publish anything.

!!!
Do not use `graduate-prerelease` to change `0.10.1-dev.N` into `0.11.0`.
Graduation only removes `-dev.N`, so it would produce `0.10.1`. Use `exact` for
the `0.11.0` release.
!!!

## 2. Verify the GitHub release

After pub.dev publication succeeds, the package workflow creates `v0.11.0` on
the release commit and dispatches the release and documentation workflows from
that tag. The release workflow creates the GitHub release with the matching
section of `packages/core/CHANGELOG.md`.

The release preparation keeps `doc/retype.yml` aligned with the `dostr_core`
version. The tag-triggered docs deployment also derives the displayed version
from the tag so the published site cannot retain a stale version label.

Verify the completed release on the
[GitHub releases page](https://github.com/relaystr/ndk/releases).

Do not create `v0.11.0` manually before package publication finishes.
Otherwise the tag can point to source that still reports the previous package
version.

## Manual alternative

1. Either change the versions manually, including dependency constraints, or
   run `melos version` (which creates a Git commit).
2. Run `melos run format`.
3. Commit your changes.
4. Run `melos publish` to validate the release, then run
   `melos publish --no-dry-run`. To publish one package, use
   `melos publish --scope=<package_name> --no-dry-run`.
