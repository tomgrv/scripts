<!-- @format -->

# git-autorebase

Automatically handle non-interactive rebasing with conflict resolution.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-autorebase` (invoke via `git autorebase`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage; fails cleanly outside a git repository
- rebases the current branch onto an explicit sha with no conflicts
- resolves a real content conflict using the default "theirs" strategy
- `-b` rebases a named branch instead of the current one
- `-o` rebases onto a named branch instead of the sha argument
- `-p` pushes the rebased branch to origin; omitted, nothing is pushed
