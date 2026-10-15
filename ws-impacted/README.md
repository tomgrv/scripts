<!-- @format -->

# ws-impacted

Print the `filter` input of
[`tomgrv/actions/list-packages`](https://github.com/tomgrv/actions/tree/main/list-packages)
that keeps only the workspaces impacted by a set of changed files.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `ws-impacted`.

## Usage

```sh
git diff --name-only HEAD^1 HEAD | ws-impacted
ws-impacted -r origin/develop...HEAD
```

| Option     | Meaning                                                            |
| ---------- | ------------------------------------------------------------------ |
| `-r range` | take the changed files from `git diff --name-only <range>`         |
| _(none)_   | read the changed files, one path per line, on standard input       |

A workspace is impacted when it owns a changed file or, transitively, depends
(`dependencies`, `peerDependencies`, `devDependencies`, `optionalDependencies`)
on one that does. Workspace directories come from [`ws-list`](../ws-list).

- Markdown impacts nobody; with only Markdown changed the filter is `false`
  (keeps no workspace).
- A changed file owned by no workspace (root manifest, shared test helpers,
  workflows…) impacts everybody: nothing is printed, which keeps every
  workspace.
- Otherwise it prints a jq expression such as
  `(.location | IN("lib","app"))`, ready for `list-packages`' `filter`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — plus `jq`, `git` and `ws-list`.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- a changed workspace impacts its transitive dependents, and only them
- a file owned by no workspace impacts everybody; Markdown impacts nobody
- `-r` takes the changed files from a git range
- the printed filter is a valid jq `select()`
