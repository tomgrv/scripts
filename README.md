# scripts

Reusable POSIX shell scripts shared across
[`tomgrv/devcontainer-features`](https://github.com/tomgrv/devcontainer-features)
(`common-utils` feature) and [`tomgrv/vps`](https://github.com/tomgrv/vps).

## Layout

Flat, one file per script at the repo root — mirrors `tomgrv/actions`'
one-purpose-per-unit model and `common-utils/bin`'s npm-linked `bin` map,
minus the per-action `action.yml`/`run.sh` subfolder GitHub Actions needs.

```
zz_wrap.sh              # core: input/output library (sourced, not run)
zz_use.sh                # core: on-demand dependency management
<verb>-<topic>.sh        # functional scripts, one per file
config/zz_use.json        # tool -> apt package / download URL map for zz_use
config/_default.schema.json
tests/*.bats
```

## Naming

- **Core** scripts keep the `zz_` prefix: `zz_wrap`, `zz_use`. These are the
  only two — everything else is a functional script.
- **Functional** scripts use `<verb>-<topic>` naming: `validate-json`,
  `normalize-json`, `merge-json`, `load-json`, `run-npx`, `dispatch-script`,
  `resolve-context`, `persist-var`, `edit-script`, `distribute-utils`,
  `install-feature`, `configure-feature`.

## `zz_wrap` — input/output library

Source it once per script:

```sh
. zz_wrap
```

Provides, as shell functions/vars (no subprocess overhead):

| Symbol                    | Purpose                                                      |
| -------------------------- | ------------------------------------------------------------- |
| `$Red` `$Green` ... `$End` | ANSI color codes                                              |
| `zz_log <lvl> <msg...>`     | colored, leveled log line on stderr (`i`/`w`/`e`/`s`/`-`)      |
| `zz_esc <value>`            | escape a value for safe re-embedding in `'...'`                |
| `zz_args <title> <caller> <<-help ...` | parse `$@` per a spec, `eval`-print `var=value` assignments |
| `zz_prompt <question> [default]` | interactive free-form input                              |
| `zz_ask <options> <question...>` | interactive single-char confirm                          |
| `zz_input [file]`           | read from arg (literal or file) or stdin                       |
| `zz_bindir [-t target]`     | resolve/create a writable bin dir, export it onto `PATH`, print it |

## `zz_use` — dependency management

Every functional script declares its dependencies in one line, up front:

```sh
zz_use jq git curl
```

For each `<tool>`, in order:

1. `command -v <tool>` — already there, no-op.
2. Look up `<tool>` in `config/zz_use.json` (override with `ZZ_USE_CONFIG`):
   - `{"apt": "<pkg>"}` → `apt-get install -y <pkg>` (via `sudo` if not root).
   - `{"url": ..., "archive": "tar.gz"|"tar.xz"|"zip"|"raw", "binpath": ...}`
     → download, extract if needed, resolve a writable bin dir via
     `zz_bindir`, and install the binary as `<tool>`. Templates support
     `{VERSION}`, `{OS}` (`uname -s`, lowercased), `{ARCH}` (`amd64`/`arm64`).
3. No config entry → fall back to `apt-get install -y <tool>` (same name).
4. Still missing afterwards → error, exit 1.

Idempotent: safe to call on every invocation — resolved tools are skipped
via `command -v` in ~0ms. Retrieval or install happens **if and only if**
the tool isn't already available.

## Functional scripts

| Script               | Purpose                                                                 |
| --------------------- | ------------------------------------------------------------------------ |
| `load-json`            | load JSON from a file/URL, tag it with `$id`                            |
| `validate-json`        | validate JSON against a (local/inferred/remote) JSON Schema             |
| `normalize-json`       | sort JSON keys per schema + alphabetically, optional in-place write     |
| `merge-json`           | recursively merge one JSON file into another (arrays deduped, unioned)  |
| `run-npx`              | run a local `node_modules/.bin` binary, falling back to `npx`           |
| `dispatch-script`      | dispatch `_foo.sh` callers to sibling `foo-<subcmd>` scripts            |
| `resolve-context`      | resolve a feature's source/target dirs from the calling script         |
| `persist-var`          | upsert a `KEY=VALUE` pair into an env file and/or `/etc/profile.d`      |
| `edit-script`          | copy an installed script locally and open it for editing                |
| `distribute-utils`     | copy `zz_*`/utility scripts into a project's local scripts directory   |
| `install-feature`      | copy a feature's stubs/config/bin into a target, run `install-*.sh`     |
| `configure-feature`    | deploy a feature's stubs into the cwd (merging), run `configure-*.sh`   |

## Usage

Install directly, or via npm:

```sh
npm install --save-dev @tomgrv/scripts
```

Every script is self-contained: it sources `zz_wrap` (falling back to a
`zz_wrap` already on `PATH` when not run from this repo) and declares its
own dependencies via `zz_use`, so any single script can be copied out or
symlinked onto `PATH` and still work standalone.

## Tests

```sh
npm test   # bats tests
```
