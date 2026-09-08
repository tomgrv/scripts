<!-- @format -->

# bump-version

Update version numbers in files listed under `bump-version.files` in
`package.json` — root files (type `json`/`plain-text`) and/or per-workspace
files (type `json@ws`/`plain-text@ws`), the latter restricted to workspaces
affected by a given commit range in `-m`/minimal mode (via
[`git-workspaces`](../git-workspaces)).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `bump-version`.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list. Also
assumes a `gitversion` CLI on `PATH` when no explicit `--version` is given —
see [`gv`](../gv).

## Tests

```sh
bats test.bats
```
