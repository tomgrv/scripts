<!-- @format -->

# json

Dispatch to json-<subcommand> utilities (json-load, json-validate, json-normalize, json-merge).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `json`, e.g. `json merge target.json source.json`
runs `json-merge target.json source.json`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- fails with no subcommand
- reports no dispatch target for an unknown subcommand
- dispatches to the matching json-<subcommand>, forwarding arguments
