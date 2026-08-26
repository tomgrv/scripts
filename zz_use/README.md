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
