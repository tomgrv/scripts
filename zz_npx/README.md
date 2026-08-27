# zz_npx

Run a local `node_modules/.bin` binary, falling back to `npx`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_npx`.

## Usage

```sh
zz_npx [-s] <tool> [args...]
```

`-s` allows npx's on-the-fly install (when the binary isn't present
locally and npx is used as a fallback) to run the package's lifecycle
scripts; by default they're skipped (`--ignore-scripts`).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
