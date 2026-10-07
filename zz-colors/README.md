# zz-colors

ANSI color variables, sourced by other zz-* scripts and functional scripts.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-colors`.

## Usage

```sh
. zz-colors
```

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- sourcing exports every documented base, bold, and underline variable
- color codes are real ANSI escape sequences (`ESC [`)
- safe to source twice with no errors
- distinct variables carry distinct codes
