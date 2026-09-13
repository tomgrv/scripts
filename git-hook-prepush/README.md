<!-- @format -->

# git-hook-prepush

Git `pre-push` hook. Validates the current branch name against this
repo's naming convention (via `validate-branch-name`) before it's pushed.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-hook-prepush` (invoke via
`git hook-prepush`, since git resolves any `git-*` executable on `PATH`
as a subcommand). Wire it up as `.git/hooks/pre-push` (directly, or via
husky) calling `git hook-prepush "$@"`.

## Usage

```sh
git-hook-prepush [<remote> [<url>]]
```

Arguments match what git passes to a `pre-push` hook.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
