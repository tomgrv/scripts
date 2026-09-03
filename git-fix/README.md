<!-- @format -->

# git-fix

Dispatch to git-fix-<subcommand> utilities.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix` (invoke via `git fix`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
