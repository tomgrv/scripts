<!-- @format -->

# distribute-utils

Copy zz-\*/utility scripts into a project's local scripts directory.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `distribute-utils`.

## Usage

```sh
distribute-utils [-t target] [-s source] [-q]
```

The target directory is resolved from, in order: `-t`, a `.zz_dist` file in the project root (target on its first line), then `config.zz_dist` in `package.json`. It must already exist; without a target the script fails, or exits 0 silently with `-q`. `-s` defaults to `/usr/local/share/common-utils`.

```sh
echo "./scripts" > .zz_dist && mkdir -p ./scripts
distribute-utils                 # target from .zz_dist
distribute-utils -t ./my-utils   # explicit target
distribute-utils -q              # no error when no target is configured
```

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
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
- copies executable `zz-*` files, stripping `_` prefix and `.sh` suffix
- skips non-executable `zz-*` files, makes copies executable in target
