# distribute-utils

Copy zz_*/utility scripts into a project's local scripts directory.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `distribute-utils`.

## Usage

```sh
distribute-utils [-t target] [-s source] [-q]
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- errors without a target, quiet no-op with `-q`
- errors when resolved target directory doesn't exist
- resolves target from `.zz_dist` and from `package.json` config
- no-op success when the source directory doesn't exist
- copies executable `zz_*` files, stripping `_` prefix and `.sh` suffix
- skips non-executable `zz_*` files, makes copies executable in target
