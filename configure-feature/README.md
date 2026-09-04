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

- help/usage output and exit code
- errors without a feature argument, or when source doesn't exist
- copies a new plain-text stub, merges a json stub into an existing file
- reconciles a text fragment additively into an existing file
- strips leading `_` prefix and `.gitignore`s `#`-prefixed stub destinations
- preserves executable bits and symlinks stub targets
- runs `configure-*.sh` scripts only from the repo top level
