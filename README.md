# scripts

Reusable POSIX `sh` scripts shared across
[`tomgrv/devcontainer-features`](https://github.com/tomgrv/devcontainer-features)
(`common-utils` feature) and [`tomgrv/vps`](https://github.com/tomgrv/vps).

## Layout

Flat, one file per atomic function at the repo root — mirrors
`tomgrv/actions`' one-purpose-per-unit model and `common-utils/bin`'s
npm-linked `bin` map, minus the per-action `action.yml`/`run.sh` subfolder
GitHub Actions needs.

```
zz_use.sh                # activator: on-demand dependency management
zz_colors.sh              # core: ANSI color vars (sourced)
zz_log.sh                  # core: leveled log line
zz_args.sh                  # core: arg parsing
zz_prompt.sh                 # core: free-form interactive input
zz_ask.sh                     # core: single-char confirm
zz_input.sh                    # core: arg/file/stdin input
zz_bindir.sh                    # core: resolve a writable bin dir
<verb>-<topic>.sh        # functional scripts, one per file
config/zz_use.json        # tool -> apt package / download URL map for zz_use
config/_default.schema.json
tests/*.bats
```

## Naming

- **Core** scripts keep the `zz_` prefix — each atomic function is its own
  dedicated script: `zz_use`, `zz_colors`, `zz_log`, `zz_args`, `zz_prompt`,
  `zz_ask`, `zz_input`, `zz_bindir`.
- **Functional** scripts use `<verb>-<topic>` naming: `validate-json`,
  `normalize-json`, `merge-json`, `load-json`, `run-npx`, `dispatch-script`,
  `resolve-context`, `persist-var`, `edit-script`, `distribute-utils`,
  `install-feature`, `configure-feature`.

## `zz_use` — the activator

`zz_use` is what every other script calls, once, up front, to declare and
resolve its dependencies — including the `zz_*` core scripts it uses:

```sh
zz_use zz_colors zz_args jq git
```

For each `<tool>` requested, in order:

1. `command -v <tool>` — already there, no-op.
2. **`zz_*` tools** — installed together, as a single bundle, the first
   time any one of them is missing (not one download/copy per script:
   they ship together and are cheap to install as a set). Source is a
   sibling `zz_*.sh` in this repo when running from a checkout/npm
   install, or a one-shot fetch of the `tomgrv/scripts` tarball otherwise.
3. **Any other tool** — looked up in `config/zz_use.json` (override with
   `ZZ_USE_CONFIG`):
   - `{"apt": "<pkg>"}` → `apt-get install -y <pkg>` (via `sudo` if not root).
   - `{"url": ..., "archive": "tar.gz"|"tar.xz"|"zip"|"raw", "binpath": ...}`
     → download, extract if needed, resolve a writable bin dir via
     `zz_bindir`, and install the binary as `<tool>`. Templates support
     `{VERSION}`, `{OS}` (`uname -s`, lowercased), `{ARCH}` (`amd64`/`arm64`).
   - No config entry → fall back to `apt-get install -y <tool>` (same name).
4. Still missing afterwards → error, exit 1.

Idempotent: safe to call on every invocation — resolved tools are skipped
via `command -v` in ~0ms. Retrieval or install happens **if and only if**
the tool isn't already available.

## Core `zz_*` scripts

| Script                       | Purpose                                                             |
| ----------------------------- | --------------------------------------------------------------------- |
| `zz_colors`                    | ANSI color vars (`$Red` `$Green` ... `$End`); source it: `. zz_colors` |
| `zz_log <lvl> <msg...>`         | colored, leveled log line on stderr (`i`/`w`/`e`/`s`/`-`)              |
| `zz_args <title> <caller> <<-help ...` | parse `$@` per a spec; `eval $(zz_args ...)` to bind the vars   |
| `zz_prompt <question> [default]` | interactive free-form input                                        |
| `zz_ask <options> <question...>` | interactive single-char confirm                                    |
| `zz_input [file]`                | read from arg (literal or file) or stdin                            |
| `zz_bindir [-t target]`          | resolve/create a writable bin dir; `eval $(zz_bindir ...)` to bind `$dir` and extend `PATH` |

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

Every functional script is self-contained: `zz_use zz_colors zz_args ...`
resolves its own dependencies (installing the `zz_*` bundle and any
external tools on first use), then `. zz_colors` picks up the color vars.
Any single script can be copied out or symlinked onto `PATH` and still
work standalone.

## Tests

```sh
npm test   # bats tests
```
