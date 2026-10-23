<!-- @format -->

# git-fix-secrets

Redact a secret from files, commit messages and/or tag annotations across all git history.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-secrets` (invoke via `git fix-secrets`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Usage

```sh
git fix-secrets [-f] [-p] [-d] [-g <glob>] [-s <secret>] [-r <repl>] [-m] [-t] <sha>
```

| Argument      | Effect                                                   |
| ------------- | -------------------------------------------------------- |
| `-f`          | allow overwriting pushed history                         |
| `-p`          | push to remote                                           |
| `-d`          | list matching commits/files without rewriting history    |
| `-g <glob>`   | glob pattern of files to search (e.g. "\*_/_.env")       |
| `-s <secret>` | secret value to redact                                   |
| `-r <repl>`   | replacement string (default: \*\*\*\*)                   |
| `-m`          | also redact the secret from commit messages              |
| `-t`          | also redact the secret from tag annotation messages      |
| `<sha>`       | sha commit to fix from (use 0 for the very first commit) |

## Examples

```sh
git fix-secrets -d -g "**/*.env" -s "my-secret-value"        # preview matching commits/files
git fix-secrets -d -m -t -g "**/*.env" -s "my-secret-value"  # also preview commit and tag messages
git fix-secrets -g "**/*.env" -s "my-secret-value"           # redact (asks for confirmation)
git fix-secrets -m -t -g "**/*.env" -s "my-secret-value" 0   # files, commit and tag messages, from the first commit
git fix-secrets -p -g "**/*.env" -s "my-secret-value"        # redact and push
git fix-secrets -g "**/*.env" -s "my-secret-value" -r "[REDACTED]"  # custom replacement (default: ****)
```

Searches all branches and tags (or starts from `<sha>`; `0` is the very first commit). Without `<sha>`, `git getcommit` resolves it.

## Notes

- The secret is matched and replaced literally (not as a regular expression); binary files are skipped.
- History is rewritten with `git filter-branch` using only `sed` and `grep`; use `-f` carefully, it allows overwriting pushed history.
- Commit hashes change: after a `-p` push everyone must re-clone or hard-reset. Rotate the leaked secret too, redacting history does not undo exposure that already happened.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage and exits non-zero
- fails cleanly outside a git repository
- requires a glob pattern and a secret value
- refuses to run with uncommitted changes
- reports no occurrences when the secret is absent, leaving files unchanged
- `-d` dry-run lists matches without modifying anything
- redacts a planted secret from tracked file content across all history
- aborts the rewrite when the user declines the confirmation prompt
- `-m` also redacts the secret from commit messages
