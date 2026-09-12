<!-- @format -->

# git-fix-lock

Fix git lock files - resolve conflicts and regenerate lock files.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-lock` (invoke via `git fix-lock`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage and exits non-zero
- is a harmless no-op outside a git repository
- does nothing when there are no lock-file conflicts
- resolves a `package-lock.json` merge conflict by keeping "ours" and
  regenerating it, leaving no conflict markers or unresolved status
