# load-json

Load JSON from a file or URL, tagging it with $id.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `load-json`.

## Usage

```sh
load-json [-s] <file-or-url>
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- errors with no source, and when the local file doesn't exist
- loads a local file and prints its content
- `-s` tags a schema file with `$id`, without overwriting an existing one
- strips `//` line comments before parsing
- returns an empty object (tagged) for a null file in schema mode
