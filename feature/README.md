<!-- @format -->

# feature

Dispatch to feature-<subcommand> utilities (feature-install, feature-configure,
feature-context).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `feature`, e.g. `feature install src/foo` runs
`feature-install src/foo`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- fails with no subcommand
- reports no dispatch target for an unknown subcommand
- dispatches to the matching feature-<subcommand>, forwarding arguments
