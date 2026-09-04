<!-- @format -->

# git-co

Git enhanced commit.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-co` (invoke via `git co`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage; missing commit message exits non-zero without committing
- plain message is left unmodified with no gitflow feature prefix configured
- `-s` injects a given scope; `-n` suppresses scope injection
- a message with an existing scope is left untouched
- derives the scope from a gitflow feature-branch prefix
- outside a git repository, the underlying `git commit` fails and nothing is committed
