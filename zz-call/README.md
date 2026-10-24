<!-- @format -->

# zz-call

Ensure a caller's declared env vars are set before running something that
needs them — vps-`dispatch.sh` style: **ask** for whatever's missing
(`zz-prompt`), **update env** by persisting the answer (`zz-persist`) so
nothing asks again next time, then **call** — either the wrapped command
with them exported, or, with no command, filtered/formatted `export
VAR='value'` lines for the caller to `eval`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-call`.

## Usage

```sh
zz-call [-p package.json[:more.json]] [-f envfile] [-P profile] [-n] [-e] [-l] [command [args...]]
```

| Flag      | Effect                                                                 |
| --------- | ---------------------------------------------------------------------- |
| `-p a:b`  | read several `package.json` files; the first definition of a var wins  |
| `-f file` | env file to read and persist (default `config.file`, else `.env`)      |
| `-P name` | also export persisted values from `/etc/profile.d/<name>.sh`           |
| `-n`      | never prompt: a missing var falls back to its `default`, not persisted |
| `-e`      | also persist values already set in the environment                     |
| `-l`      | list the declared inputs (var, question, required, default, secret)    |

`config.inputs` is the canonical form; `config.input` (an array, the only one that existed before) stays as a deprecated alias. Besides it, `config.ports` (each `{name, port, access}` is the var `<NAME>_PORT`, defaulting to the port) and `config.inputs` (an object keyed by var, with
`description`, `default`, `required`, `secret`, `as`) is read. Resolution order: environment,
then the env file (read literally, never sourced), then a prompt. A `secret`
input is only flagged to `zz-persist` (`-s`), which asks for it masked and
refuses any target that others can read: `zz-call` has no secret handling of
its own.

What to check/ask/set, and what to print back, is declared in a
`package.json` (default: `./package.json` — the caller's own, since every
script in this repo has one right next to its `run.sh`) under `config`.
`input` and `output` entries share one schema:

```json
{
    "config": {
        "file": ".env",
        "input": [
            {
                "var": "DB_HOST",
                "question": "Database host?",
                "default": "localhost"
            },
            {
                "var": "DB_PASSWORD",
                "question": "Database password?",
                "as": "PGPASSWORD"
            }
        ],
        "output": [
            { "var": "DB_HOST" },
            { "var": "DB_PASSWORD", "as": "PGPASSWORD" }
        ]
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
  offered to `zz-prompt` when `var` is missing.

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

With a command, `zz-call` `exec`s it with every input var exported:

```sh
zz-call psql -c '\l'
```

With no command, it prints the `output`-filtered export lines for the
caller to `eval` — the same pattern `zz-bindir` uses for `$dir`:

```sh
eval "$(zz-call)"
```

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- prompts, persists to `.env`, and an `as` entry renames the eval'd export
- already-set env vars are used as-is: no prompt, nothing new persisted
- with a wrapped command, both `var` and its `as` alias are exported to it
- an explicit `output` array filters which vars get printed
- errors when no `package.json` is found
- a missing var's default is offered, and persisted when accepted
- `-p` points at a non-default `package.json` path
- `config.file` redirects persistence to a non-`.env` target
- `config.inputs` from several package.json files, first definition wins
- `-n` never prompts or persists defaults; the env file is read literally
- `-f`/`-e`/`-P` choose the file, persist environment values, export via profile.d
- a `secret` input is asked and persisted by `zz-persist -s` into an owner-only file
