# validate-json

Validate JSON against a local/inferred/remote JSON Schema.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `validate-json`.

## Usage

```sh
validate-json [-a] [-i] [-f fallback] [-l local] [-s schema] <json>
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
