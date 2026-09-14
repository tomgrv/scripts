<!-- @format -->

# git-hook-precommit

Git `pre-commit` hook. Keeps `package-lock.json`/`composer.lock` in sync
with any staged manifest changes, installs missing prettier plugins via
`git-hook-installplugins`, then runs `git-precommit-checks` and
`lint-staged` against the staged files.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-hook-precommit` (invoke via
`git hook-precommit`, since git resolves any `git-*` executable on `PATH`
as a subcommand). Wire it up as `.git/hooks/pre-commit` (directly, or via
husky) calling `git hook-precommit "$@"`.

## Usage

```sh
git-hook-precommit [<pathspec>...]
```

With no arguments, diffs the staged (`--cached`) files; with arguments,
diffs against those refs/paths instead — same as `git diff --name-only`.
Skips entirely when `$GIT_COMMAND` is `rebase`.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.
Also shells out to `npm` and, when a `composer.json` changed, `composer`.

## Tests

```sh
bats test.bats
```
