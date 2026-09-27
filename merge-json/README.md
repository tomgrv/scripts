# merge-json

Recursively merge one JSON file into another, arrays deduped and unioned.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `merge-json`.

## Usage

```sh
merge-json [-t tabSize] <target> <source>
```

## Dependencies

Declared as `peerDependencies` in `package.json` and installed by `zz_use`
alongside this script (only if missing) — see `package.json` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- errors with no arguments, only a target, or a missing target file
- errors when the target file is not valid JSON
- merges a source object into the target file in place
- merges from stdin when source is `-`
- unions and dedupes array values, recursively merges nested objects
- `-t` sets the written indentation size
