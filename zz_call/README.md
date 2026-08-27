# zz_call

Ensure a caller's declared env vars are set before running something that
needs them — vps-`dispatch.sh` style: **ask** for whatever's missing
(`zz_prompt`), **update env** by persisting the answer (`zz_persist`) so
nothing asks again next time, then **call** — either the wrapped command
with them exported, or, with no command, filtered/formatted `export
VAR='value'` lines for the caller to `eval`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_call`.

## Usage

```sh
zz_call [-p package.json] [command [args...]]
```

What to check/ask/set, and what to print back, is declared in a
`package.json` (default: `./package.json` — the caller's own, since every
script in this repo has one right next to its `run.sh`) under `config`:

```json
{
    "config": {
        "file": ".env",
        "input": [
            { "var": "DB_HOST", "question": "Database host?", "default": "localhost" },
            { "var": "DB_PASSWORD", "question": "Database password?" }
        ],
        "output": ["DB_HOST", { "var": "DB_PASSWORD", "as": "PGPASSWORD" }]
    }
}
```

- **`input`** — one entry per env var to ensure is set. Each is checked
  against the environment first; only a missing (unset/empty) one is
  asked for (`question`, offering `default`) and persisted (to `file`,
  default `.env`). An already-set var is used as-is: nothing is asked,
  and nothing new is persisted for it.
- **`output`** — which resolved vars to print as `export NAME='value'`
  lines, and under what name. Each entry is either a plain var name
  (string) or `{"var": "<source>", "as": "<exported-as>"}` to rename on
  the way out. Defaults to every `input` var, printed under its own name,
  when `output` is omitted.

With a command, `zz_call` `exec`s it with every input var exported:

```sh
zz_call psql -c '\l'
```

With no command, it prints the `output`-filtered export lines for the
caller to `eval` — the same pattern `zz_bindir` uses for `$dir`:

```sh
eval "$(zz_call)"
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
