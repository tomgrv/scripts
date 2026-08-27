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
script in this repo has one right next to its `run.sh`) under `config`.
`input` and `output` entries share one schema:

```json
{
    "config": {
        "file": ".env",
        "input": [
            { "var": "DB_HOST", "question": "Database host?", "default": "localhost" },
            { "var": "DB_PASSWORD", "question": "Database password?", "as": "PGPASSWORD" }
        ],
        "output": [{ "var": "DB_HOST" }, { "var": "DB_PASSWORD", "as": "PGPASSWORD" }]
    }
}
```

Each entry is `{"var": "<name>", "as": "<export-name>", "question": "...", "default": "..."}`:

- **`var`** (required) — the env var checked, prompted for, and persisted.
- **`as`** (optional, default: `var`) — the name it's exported/printed
  under, letting a command see a differently-named var than the one that
  was actually asked/persisted (e.g. ask for `DB_PASSWORD`, export it to a
  `psql`-invoked command as `PGPASSWORD`).
- **`question`**/**`default`** — only meaningful on an `input` entry,
  offered to `zz_prompt` when `var` is missing.

`input` is checked against the environment first; only a missing
(unset/empty) `var` is asked for and persisted (to `file`, default
`.env`) — always under `var`, regardless of `as`. An already-set var is
used as-is: nothing is asked, and nothing new is persisted for it. Every
input entry is exported under `var`, and additionally under `as` when the
two differ (so a wrapped command sees both names).

`output` — which resolved vars to print as `export <as>='value'` lines,
reading each one's current value from `var`. Defaults to the `input` list
itself when `output` is omitted (so a lone `as` on an input entry, as
above, already renames the eval'd output with no separate `output` array
needed).

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
