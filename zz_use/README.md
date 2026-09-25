<!-- @format -->

# zz_use

Activator: on-demand dependency management (apt/download, and single-shot zz_* bundle install).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_use`.

## Usage

```sh
zz_use "<tool>" [tool...]
zz_use [tool...] -x "<tool>" [arg...] # install <tool>, then exec it
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- skips a tool already on PATH, reporting "already available"
- requires at least one tool argument
- prints its usage error even when zz_log isn't resolvable yet
- rejects an unknown option instead of treating it as a tool name
- installs a functional script individually, not the whole set
- installs a single zz_* tool individually, not the whole set
- errors with "Unable to provide required dependency" when a tool can't be resolved
- `--force` re-installs a zz_* tool even when already on PATH
- recognizes `--force` after a tool name, not just as the first arg
- resolves a functional script's `config/` folder alongside it
- `-x` installs the target and execs it, passing arguments through
- `-x` propagates the exec'd command's exit status
- `-x` resolves leading dependencies before installing/exec'ing the target
- `-x` strips an `[org/repo/]` prefix from the exec target's command name
- `-x` without a tool name errors
