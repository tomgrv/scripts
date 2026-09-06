<!-- @format -->

# git-unset

Unset all Git config keys starting with the given prefix.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-unset` (invoke via `git unset`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- unsets all local keys matching the given prefix, leaving others intact
- is a no-op when nothing matches the prefix
- defaults to matching any lower-case prefix when none is given
- operates on a different config scope (e.g. `--global`) when given as second argument
- fails cleanly outside a git repository
