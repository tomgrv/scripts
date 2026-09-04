<!-- @format -->

# git-getcommit

List git history and ask for a commit to fix up.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-getcommit` (invoke via `git getcommit`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- prints the resolved full sha for a given commit
- resolves an abbreviated sha to the full sha
- treats sha `0` as the very first commit in history
- `-p` prints the parent of the given commit
- prints nothing (without crashing) for an unresolvable sha
