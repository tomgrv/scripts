# zz_use

Activator: on-demand dependency management (apt/download, and single-shot zz_* bundle install).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_use`.

## Usage

```sh
zz_use <tool> [tool...]
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
- installs a functional script individually, not the whole bundle
- installing any one missing zz_* tool installs the full zz_* bundle at once
- errors with "Unable to provide required dependency" when a tool can't be resolved
- `--force` re-installs the bundle even when already on PATH
- resolves a functional script's `config/` folder alongside it
