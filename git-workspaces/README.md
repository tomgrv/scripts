<!-- @format -->

# git-workspaces

List workspace directories and affected workspaces.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-workspaces` (invoke via `git workspaces`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
