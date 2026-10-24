<!-- @format -->

# json-normalize

Sort JSON object keys per schema and alphabetically, optional in-place write.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `json-normalize`.

## Usage

```sh
json-normalize [-w] [-t tabSize] [-f fallback] [-l local] [-i] [-s schema] <files...>
```

Validates the file first (see `json-validate`), then orders keys by the schema definition, then alphabetically.

| Option      | Effect                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------- |
| `-w`        | write the result back to the file                                                                 |
| `-t <size>` | tab size for indentation                                                                          |
| `-c`        | cache schema validation maps                                                                      |
| `-a`        | allow additional properties at the root level                                                     |
| `-d`        | debug output                                                                                      |
| `-f <file>` | fallback schema (`local` targets the feature folder's default schemas)                            |
| `-l <path>` | infer the schema from a local folder based on the file name (`x.y.json` → `<path>/y.schema.json`) |
| `-i`        | infer the schema from the JSON Schema Store when nothing is found locally                         |
| `-s <file>` | schema file or URL                                                                                |

With `lint-staged`: `"*.json": ["json-normalize -c -w -a -i -t 4 -f local -l true"]`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- sorts keys and prints to stdout without touching the file (no `-w`)
- `-w` writes the normalized result back to the file
- refuses `-w` when reading from stdin
- reads from stdin and normalizes multiple file arguments
- reports (without crashing) a file that does not exist
- errors when the file fails schema validation
