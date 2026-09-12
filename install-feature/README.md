# install-feature

Copy a feature's stubs/config/bin into a target, run install-*.sh.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `install-feature`.

## Usage

```sh
install-feature [-s source] [-t target] <caller>
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- errors without a caller argument
- copies stubs/config/bin from source to target
- copies `configure-*.sh` lifecycle scripts, runs `install-*.sh` ones
- symlinks `bin/*.sh` scripts (stripping `.sh`) onto a writable PATH dir
- warns but still succeeds when source has no stubs/config
