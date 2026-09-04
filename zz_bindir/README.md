# zz_bindir

Resolve (and create if needed) a writable bin directory on PATH.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_bindir`.

## Usage

```sh
eval "$(zz_bindir [-t target])"
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- resolves a writable dir and prints `dir=...`
- prefers a dir already on PATH over creating a new one, skipping the `export PATH` line
- emits `export PATH=...` when the chosen dir isn't already on PATH
- `-t target` creates and uses `<target>/bin` when nothing writable already exists
- `eval "$(zz_bindir)"` usage extends `PATH` and sets `$dir`
- fails with a non-zero exit when no writable dir can be found or created
