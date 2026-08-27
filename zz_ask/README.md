# zz_ask

Interactive single-character confirm/choice prompt.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_ask`.

## Usage

```sh
choice=$(zz_ask "Yn" "Continue?")
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
