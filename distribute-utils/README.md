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
