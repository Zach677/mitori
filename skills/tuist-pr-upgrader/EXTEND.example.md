# Tuist PR Upgrader configuration example

The upgrader loads the first `toml` fenced block it finds and uses the values to drive discovery, verification, and whether push/PR actions may run.

```toml
scan_roots = ["/path/to/repos", "/another/path"]
allow_push = false
allow_pr = false

[repos.mitori]
path = "/path/to/repos/mitori"
verify_commands = ["mise run test-macos"]
base_branch = "main"
```

- `scan_roots` defines where the tool will search for Tuist repositories.
- `allow_push` and `allow_pr` gate whether the skill may push branches or open PRs after upgrades.
- Each entry under `[repos.<name>]` lets you pin per-repo paths, verification commands, and an optional `base_branch` override.
