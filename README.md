# scripts

Reusable POSIX `sh` scripts shared across
[`tomgrv/devcontainer-features`](https://github.com/tomgrv/devcontainer-features)
(`common-utils` feature) and [`tomgrv/vps`](https://github.com/tomgrv/vps).

## Layout

One folder per script (an npm workspace), each self-contained:

```
<name>/
  run.sh          # the script; linked onto PATH as `<name>`
  package.json    # {"name": "<name>", "bin": {"<name>": "run.sh"}, ...}
  README.md       # usage + dependencies for this one script
  test.bats       # bats tests for this script
  config/         # optional: resources owned by this script only
                  #   (validate-json/config/, zz_use/config/zz_use.json)
tests/helpers.bash # shared bats setup: links every <name>/run.sh onto PATH
package.json       # npm workspaces root, listing every folder above
setup.sh            # root bootstrapper: temp-downloads the core zz_* scripts
```

Modeled on `tomgrv/actions`' one-folder-per-unit convention (`<action>/`
with its own `action.yml`/`run.sh`/`package.json`), adapted for plain
shell scripts instead of composite GitHub Actions.

## `setup.sh` — root bootstrap

A machine with nothing installed yet needs *something* fetchable with zero
prerequisites. That's `setup.sh`, kept deliberately dumb and DRY: it
downloads a tarball of this repo to a temp dir, then hands off to the
`zz_use` it just downloaded to install the core `zz_*` bundle from
there — the same bin-dir resolution and linking logic `zz_use` always
uses, not a second copy of it — and discards the temp dir.

```sh
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
```

That's the only thing that needs fetching up front. Once `zz_use` is on
`PATH`, every other script — core or functional — resolves and installs
its own further dependencies on demand the same way (see `zz_use` below).
Functional scripts themselves aren't installed by `setup.sh` or `zz_use`;
install those directly (`npm install <folder>`, or check out the repo).

## Caching and `zz_update`

Both `setup.sh` and `zz_use`'s zz_* bundle install resolve the same way:
straight from disk when running inside a checkout of this repo, otherwise
from a local cache directory (`ZZ_CACHE_DIR`, default
`~/.cache/zz_scripts`) that's populated on first use and then just linked
from on every call after that — no repeat network round-trip.

`zz_update` forces a fresh download, bypassing the cache, and re-links the
core `zz_*` scripts from it:

```sh
zz_update              # or: zz_use --force <tool...>
```

## Naming

- **Core** folders keep the `zz_` prefix — each atomic function is its own
  dedicated script: `zz_use`, `zz_update`, `zz_colors`, `zz_log`, `zz_args`,
  `zz_prompt`, `zz_ask`, `zz_input`, `zz_bindir`, `zz_dispatch`, `zz_npx`,
  `zz_persist`.
- **Functional** folders use `<verb>-<topic>` naming: `validate-json`,
  `normalize-json`, `merge-json`, `load-json`, `resolve-context`,
  `edit-script`, `distribute-utils`, `install-feature`,
  `configure-feature`.

## `zz_use` — the activator

`zz_use` is what every other script calls, once, up front, to declare and
resolve its dependencies — including any other script in this repo, core
or functional:

```sh
zz_use zz_colors zz_args load-json jq git
```

Internally, `run.sh` is a thin wrapper around a `_use()` function that does
the actual resolving. Every helper it calls (`_bindir`, `_install_zz_bundle`,
`_install_repo_script`, ...) is self-sufficient — none of them require
`zz_bindir`, `zz_log`, or any other core script to already be on `PATH`.
That's what lets `zz_use` bootstrap the whole core `zz_*` bundle from
nothing: the very first `zz_use zz_colors ...` a freshly downloaded,
standalone `zz_use` ever runs (e.g. from `setup.sh`) needs none of its own
dependencies installed first.

For each `<tool>` requested, in order:

1. `command -v <tool>` — already there, no-op.
2. **`zz_*` core tools** — installed together, as a single bundle, the
   first time any one of them is missing (not one download/copy per
   script: they ship together and are cheap to install as a set).
3. **Any other tool with a `zz_use/config/zz_use.json` entry** (override
   with `ZZ_USE_CONFIG`) — an explicit mapping always wins if a name
   happens to collide with a repo script:
   - `{"apt": "<pkg>"}` → `apt-get install -y <pkg>` (via `sudo` if not root).
   - `{"url": ..., "archive": "tar.gz"|"tar.xz"|"zip"|"raw", "binpath": ...}`
     → download, extract if needed, resolve a writable bin dir via
     `zz_bindir`, and install the binary as `<tool>`. Templates support
     `{VERSION}`, `{OS}` (`uname -s`, lowercased), `{ARCH}` (`amd64`/`arm64`).
4. **Any other script from this repo** (a functional script like
   `load-json`, or a core one requested individually) — installed on its
   own, not as part of the bundle: unlike the core set, functional
   scripts aren't all needed together. Source for both 2 and 4 is, in
   order: a sibling `zz_*/run.sh` folder in this repo when running from a
   checkout/npm install; otherwise a local cache (see caching below);
   otherwise a fresh download into that cache.
5. No config entry, not a script in this repo → fall back to
   `apt-get install -y <tool>` (same name).
6. Still missing afterwards → error, exit 1.

Idempotent: safe to call on every invocation — resolved tools are skipped
via `command -v` in ~0ms. Retrieval or install happens **if and only if**
the tool isn't already available.

## Core `zz_*` scripts

| Script                       | Purpose                                                             |
| ----------------------------- | --------------------------------------------------------------------- |
| `zz_update`                     | force a fresh download of the zz_* bundle, bypassing the local cache  |
| `zz_colors`                    | ANSI color vars (`$Red` `$Green` ... `$End`); source it: `. zz_colors` |
| `zz_log <lvl> <msg...>`         | colored, leveled log line on stderr (`i`/`w`/`e`/`s`/`-`)              |
| `zz_args <title> <caller> <<-help ...` | parse `$@` per a spec; `eval $(zz_args ...)` to bind the vars   |
| `zz_prompt <question> [default]` | interactive free-form input                                        |
| `zz_ask <options> <question...>` | interactive single-char confirm                                    |
| `zz_input [file]`                | read from arg (literal or file) or stdin                            |
| `zz_bindir [-t target]`          | resolve/create a writable bin dir; `eval $(zz_bindir ...)` to bind `$dir` and extend `PATH` |
| `zz_dispatch <caller> <subcmd>`  | dispatch an underscore-prefixed caller to a sibling `<name>-<subcmd>` script |
| `zz_npx [-s] <tool>`             | run a local `node_modules/.bin` binary, falling back to `npx`         |
| `zz_persist [-f\|-p] <key> <value>` | upsert a `KEY=VALUE` pair into an env file and/or `/etc/profile.d`  |

## Functional scripts

| Script               | Purpose                                                                 |
| --------------------- | ------------------------------------------------------------------------ |
| `load-json`            | load JSON from a file/URL, tag it with `$id`                            |
| `validate-json`        | validate JSON against a (local/inferred/remote) JSON Schema             |
| `normalize-json`       | sort JSON keys per schema + alphabetically, optional in-place write     |
| `merge-json`           | recursively merge one JSON file into another (arrays deduped, unioned)  |
| `resolve-context`      | resolve a feature's source/target dirs from the calling script         |
| `edit-script`          | copy an installed script locally and open it for editing                |
| `distribute-utils`     | copy `zz_*`/utility scripts into a project's local scripts directory   |
| `install-feature`      | copy a feature's stubs/config/bin into a target, run `install-*.sh`     |
| `configure-feature`    | deploy a feature's stubs into the cwd (merging), run `configure-*.sh`   |

See each folder's own `README.md` for its usage line.

## Usage

Install the whole workspace, or a single script's own package:

```sh
npm install --save-dev @tomgrv/scripts   # everything
# or, e.g.:
npm install --save-dev ./validate-json    # just this one, standalone
```

Every functional script is self-contained: `zz_use zz_colors zz_args ...`
resolves its own dependencies (installing the `zz_*` bundle and any
external tools on first use), then `. zz_colors` picks up the color vars.
Any single folder can be copied out and still work standalone.

## Tests

```sh
npm test                       # bats --recursive . (every */test.bats)
bats validate-json/test.bats   # a single script's tests
```
