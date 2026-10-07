<!-- @format -->

# git-fix-orphans

Prefix every remote branch that does not follow the gitflow config and has no
pull request with `orphan/` (`my-experiment` becomes `orphan/my-experiment`).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-orphans` (invoke via `git fix-orphans`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Usage

```sh
git fix-orphans    # dry run: list the branches that would be renamed
git fix-orphans -p # rename them on the remote
git fix-orphans -x stale/ upstream
```

A branch is left alone when it:

- is `gitflow.branch.master`, `gitflow.branch.develop` or the remote's default branch
- starts with a `gitflow.prefix.*` (feature, bugfix, release, hotfix, support) or with the orphan prefix
- is, or ever was, the head of a pull request (`gh pr list --state all`)
- would collide with an existing `<prefix><branch>`

Without any gitflow config (`gitflow.branch.*`) the script does nothing. If
`gh` cannot list pull requests, it aborts without renaming anything.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list. Needs
the `gh` CLI, authenticated (`GH_TOKEN`).

## Tests

```sh
bats test.bats
```
