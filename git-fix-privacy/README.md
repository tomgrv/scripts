<!-- @format -->

# git-fix-privacy

Fix privacy in history.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-privacy` (invoke via `git fix-privacy`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Usage

```sh
git fix-privacy [-f] [-p] [-o <old>] [-n <new>] [-a <author>] <sha>
```

| Argument      | Effect                      |
| ------------- | --------------------------- |
| `-f`          | force overwrite backup      |
| `-p`          | push to remote              |
| `-o <old>`    | old email to replace        |
| `-n <new>`    | new name to replace with    |
| `-a <author>` | author name to replace with |
| `<sha>`       | sha commit to start from    |

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage and exits non-zero
- fails cleanly outside a git repository
- rewrites author name/email across history and updates local git config
- leaves commits by a different author untouched
