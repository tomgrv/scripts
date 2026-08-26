# run-npx

Run a local node_modules/.bin binary, falling back to npx.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `run-npx`.

## Usage

```sh
run-npx [-s] <tool> [args...]
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
