<!-- @format -->

# bump-version

Update version numbers in files listed under `bump-version.files` in
`package.json` — root files (type `json`/`plain-text`) and/or per-workspace
files (type `json@ws`/`plain-text@ws`), the latter restricted to workspaces
affected by a given commit range in `-m`/minimal mode (via
[`ws-list`](../ws-list)).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `bump-version`.

## Usage

```sh
bump-version [-m] [-r <range>] [-d] <version>
```

| Argument     | Effect                                                                   |
| ------------ | ------------------------------------------------------------------------ |
| `-m`         | Only bump workspace files if commit scope relates to workspace name      |
| `-r <range>` | Git range to check for affected workspaces (required for minimal mode)   |
| `-d`         | Show what would be updated without making changes                        |
| `<version>`  | Version to set in files (optional - will use GitVersion if not provided) |

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list. Also
assumes a `gitversion` CLI on `PATH` when no explicit `--version` is given —
see [`gv`](../gv).

## Tests

```sh
bats test.bats
```
