<!-- @format -->

# zz

Front door to the `zz-*` family: run `zz-<name>` when it is installed, otherwise
install `<name>` on demand and run it.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz`.

## Usage

```sh
zz <name> [args...]
```

- `zz log i "hello"` runs `zz-log i "hello"` (a normal dispatcher).
- `zz json merge a.json b.json` has no `zz-json`, so it runs
  `zz-use -x json merge a.json b.json`: installs `json` if missing, then execs it.

The exit status is the target's. Without arguments (or with `-h`) it prints its
usage and exits non-zero.

## Dependencies

None at load time (not even `zz-log`), so it works before anything else is
installed; the fallback path needs `zz-use` on `PATH`.

## Tests

```sh
bats test.bats
```

- fails with usage and a non-zero status without arguments
- runs `zz-<name>` when it exists, forwarding arguments and exit status
- prefers `zz-<name>` over installing `<name>`
- falls back to `zz-use -x <name>` when `zz-<name>` does not exist
