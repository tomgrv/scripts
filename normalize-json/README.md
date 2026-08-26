# normalize-json

Sort JSON object keys per schema and alphabetically, optional in-place write.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `normalize-json`.

## Usage

```sh
normalize-json [-w] [-t tabSize] [-f fallback] [-l local] [-i] [-s schema] <files...>
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
