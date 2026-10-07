<!-- @format -->

# yaml

Dispatch to yaml-<subcommand> utilities (yaml-merge).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `yaml`, e.g. `yaml merge target.yaml source.yaml`
runs `yaml-merge target.yaml source.yaml`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- fails with no subcommand
- reports no dispatch target for an unknown subcommand
- dispatches to the matching yaml-<subcommand>, forwarding arguments
