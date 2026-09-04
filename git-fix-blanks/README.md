<!-- @format -->

# git-fix-blanks

Discard changes made only of whitespace, blanks, quote/slash swaps.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-blanks` (invoke via `git fix-blanks`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage
- with no modified tracked files, reports nothing to do
- `-d` dry-run reports discardable whitespace-only changes without touching the working tree
- discards a whitespace-only modification and a comment-only change in a `.sh` file
- keeps a real content change
- deleted tracked files are left untouched (diff-filter=M excludes deletions)
- outside a git repository, exits cleanly reporting no modified files
