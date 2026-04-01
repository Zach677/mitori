# Tuist PR Upgrader config schema

## Top-level fields

- `scan_roots` (`array<string>`): Absolute or relative paths that the upgrader will search for Tuist repositories. The discovery step enumerates each directory under these roots.
- `include_repos` (`array<string>`): Optional allow-list of repo names that should be considered even when they live under scan roots but would otherwise be skipped. Defaults to an empty list.
- `exclude_repos` (`array<string>`): Optional block-list of repo names to omit from upgrades even if they appear under the scan roots.
- `allow_push` (`boolean`): Gate for whether the orchestrator is allowed to push branches back to the remote repositories. When `false`, the upgrader must stop after preparing the diff.
- `allow_pr` (`boolean`): Gate for whether the tool may open pull requests after a successful upgrade. When `false`, it should only report the planned changes.

## Repos table

Each repo receives an entry under `[repos.<name>]` that declares how to handle that repository specifically.

```toml
[repos.mitori]
path = "/tmp/repos/mitori"
verify_commands = ["mise run test-macos"]
base_branch = "main"
```

- `path` (`string`): A path to the repo root that must match one of the discovered candidates.
- `verify_commands` (`array<string>`): Commands the tool should run for validation before reporting success.
- `base_branch` (`string`, optional): The base branch that the repo should stay on when generating upgrades; it is allowed to be omitted.
