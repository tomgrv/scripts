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

- help/usage output and exit code
- fails with no arguments, on a missing file, or with no schema resolvable
- validates against an explicit schema file and a local fallback schema
- rejects a missing required property and a wrong property type
- infers the schema from a local folder based on file suffix
- rejects a malformed JSON file
