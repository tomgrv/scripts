<!-- @format -->

# git-fix-prune

Prune remote-tracking references that no longer exist on the remote.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-prune` (invoke via `git fix-prune`, since
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
- removes stale remote-tracking refs for a branch deleted on the remote
- accepts an explicit remote name
