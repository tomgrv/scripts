<!-- @format -->

# git-hook-preparecommitmsg

Git `prepare-commit-msg` hook. Installs commitizen/commitlint plugins via
`git-hook-installplugins`, then launches `git-cz`'s interactive prompt to
build the commit message — skipped when a message was already supplied
(merge/squash/template commits, or `commit -m`).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-hook-preparecommitmsg` (invoke via
`git hook-preparecommitmsg`, since git resolves any `git-*` executable on
`PATH` as a subcommand). Wire it up as `.git/hooks/prepare-commit-msg`
(directly, or via husky) calling `git hook-preparecommitmsg "$@"`.

## Usage

```sh
git-hook-preparecommitmsg <msgfile> [source] [commit]
```

Arguments match what git passes to a `prepare-commit-msg` hook.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
