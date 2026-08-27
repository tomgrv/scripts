# configure-feature

Deploy a feature's stubs into the cwd (merging), run configure-*.sh.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `configure-feature`.

## Usage

```sh
configure-feature [-s source] <feature>
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
