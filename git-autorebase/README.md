<!-- @format -->

# git-autorebase

Automatically handle non-interactive rebasing with conflict resolution.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-autorebase` (invoke via `git autorebase`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Usage

```sh
git autorebase [-f] [-p] [-a] [-n] [-s <strategy>] [-o <onto>] [-b <branch>] <sha>
```

| Argument        | Effect                                              |
| --------------- | --------------------------------------------------- |
| `-f`            | allow overwriting pushed history                    |
| `-p`            | push to remote after rebase                         |
| `-a`            | Apply autosquash (default: off)                     |
| `-n`            | don't automatically manage lock files               |
| `-s <strategy>` | strategy for conflicts (default: theirs)            |
| `-o <onto>`     | rebase onto (default: origin/main)                  |
| `-b <branch>`   | branch to rebase (default: current branch)          |
| `<sha>`         | commit/branch to rebase onto (default: origin/main) |

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage; fails cleanly outside a git repository
- rebases the current branch onto an explicit sha with no conflicts
- resolves a real content conflict using the default "theirs" strategy
- `-b` rebases a named branch instead of the current one
- `-o` rebases onto a named branch instead of the sha argument
- `-p` pushes the rebased branch to origin; omitted, nothing is pushed
