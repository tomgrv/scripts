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

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list. Needs
the `gh` CLI, authenticated (`GH_TOKEN`).

## GitLab CI

Inside GitLab CI (`GITLAB_CI=true`) the merge requests are listed through the
GitLab REST API (`curl`, `jq`, up to 1000) instead of `gh`, and with `-p` the
remote is switched to `https://oauth2:$GITLAB_TOKEN@$CI_SERVER_HOST/$CI_PROJECT_PATH.git`
to push the renames. Set `GITLAB_TOKEN` to a project access token with the
`api` and `write_repository` scopes. If the API cannot be read, nothing is renamed.

## Tests

```sh
bats test.bats
```
