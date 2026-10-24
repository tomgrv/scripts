<!-- @format -->

# json-validate

Validate JSON against a local/inferred/remote JSON Schema.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `json-validate`.

## Usage

```sh
json-validate [-a] [-i] [-f fallback] [-l local] [-s schema] <json>
```

| Option      | Effect                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------- |
| `-a`        | allow additional properties at the root level                                                     |
| `-d`        | debug output                                                                                      |
| `-c`        | cache schema validation maps                                                                      |
| `-f <file>` | fallback schema when none is found locally or inferred                                            |
| `-l <path>` | infer the schema from a local folder based on the file name (`x.y.json` → `<path>/y.schema.json`) |
| `-i`        | infer the schema from the JSON Schema Store when nothing is found locally                         |
| `-s <file>` | schema file or URL to validate against                                                            |

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
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
