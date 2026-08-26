# zz_wrap

Ensure an env var is set before running something that needs it —
vps-`dispatch.sh` style: **ask** for it if it's missing (`zz_prompt`),
**call** the wrapped command with it exported, and **update env** by
persisting the answer (`zz_persist`) so nothing asks again next time.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_wrap`.

## Usage

```sh
zz_wrap -v VAR [-q "question?"] [-d default] [-f file] [command [args...]]
```

If `$VAR` is already set (non-empty) in the environment, it's used as-is —
nothing is asked, and nothing new is persisted (there's nothing new to
persist).

With a command, `zz_wrap` `exec`s it with `VAR` exported:

```sh
zz_wrap -v DB_PASSWORD -q "Database password?" psql -c '\l'
```

With no command, it prints an `export VAR='value'` line for the caller to
`eval` — the same pattern `zz_bindir` uses for `$dir`:

```sh
eval "$(zz_wrap -v DB_PASSWORD -q "Database password?")"
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
