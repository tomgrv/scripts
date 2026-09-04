<!-- @format -->

# git-fix-author

Set user.name and user.email to a specified commit's author.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-author` (invoke via `git fix-author`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage without touching any config
- fails cleanly outside a git repository
- copies user.name/user.email from a given commit's author into local config
- always removes the global user section, even before setting the local one
- an invalid sha leaves existing local config untouched
