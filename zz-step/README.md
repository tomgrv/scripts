<!-- @format -->

# zz-step

The `up|down|summary` entry point of a setup step, sourced as the last line of its `run.sh`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-step`.

## Usage

```sh
up() { ...; }
down() { ...; }
summary() { ...; }   # optional

. zz-step
```

`./run.sh up|down|summary` calls the matching function; anything else logs a usage error and exits 1. A step without `summary()` ends silently on `summary`.

## Tests

```sh
bats test.bats
```
