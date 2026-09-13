# merge-yaml

Recursively merge one YAML file into another, arrays deduped and unioned.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `merge-yaml`. Mirrors `merge-json`'s semantics
(same recursive-merge/array-dedupe rules), round-tripping through JSON so
both tools share one merge implementation.

## Usage

```sh
merge-yaml [-i indent] <target> <source>
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- errors with no arguments, only a target, or a missing target file
- errors when the target file is not valid YAML
- merges a source object into the target file in place
- merges from stdin when source is `-`
- unions and dedupes array values, recursively merges nested objects
- `-i` sets the written indentation size
