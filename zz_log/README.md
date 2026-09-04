# zz_log

Colored, leveled log line on stderr (i/w/e/s/-).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_log`.

## Usage

```sh
zz_log <i|w|e|s|-> <message...>
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- writes to stderr, never stdout
- each of i/w/e/s/- picks the right pictogram (→, !, ✕, ✔, none)
- an unknown level falls back to printing the level string itself
- multiple message words are joined with spaces
- `{Color text}` inline highlight syntax is supported
