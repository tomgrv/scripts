<!-- @format -->

# scripts

Reusable shell scripts shared across
[`tomgrv/devcontainer-features`](https://github.com/tomgrv/devcontainer-features)
(`common-utils` feature) and [`tomgrv/vps`](https://github.com/tomgrv/vps).
Every core `zz_*` script and most functional scripts are POSIX `sh`; a
few functional scripts ported from the original bash implementation
(`validate-json`, `normalize-json`) keep `#!/bin/bash` for now, since
they rely on bash-only features (arrays, `<<<`, `${var//pat/rep}`).

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

A machine with nothing installed yet needs _something_ fetchable with zero
prerequisites. That's `setup.sh`, kept deliberately dumb and DRY: it
downloads a tarball of this repo to a temp dir, then hands off to the
`zz_use` it just downloaded to install the core `zz_*` bundle from
there — the same bin-dir resolution and linking logic `zz_use` always
uses, not a second copy of it — and discards the temp dir.

```sh
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
```

Pin it to a tag, branch, or commit instead of `main` with a positional arg
or `ZZ_ORIGIN_REF`, or bootstrap from a different org/repo entirely with
`ZZ_ORIGIN`:

```sh
curl -fsSL .../setup.sh | sh -s -- v2
```

Both are exported for the `zz_use` this hands off to (and anything it
execs), so every `zz_use` call afterwards defaults to this same origin —
wherever this install actually came from — rather than a hardcoded
`tomgrv/scripts`.

That's the only thing that needs fetching up front. Once `zz_use` is on
`PATH`, every other script — core or functional — resolves and installs
its own further dependencies on demand the same way (see `zz_use` below).
Functional scripts themselves aren't installed by `setup.sh` or `zz_use`;
install those directly (`npm install <folder>`, or check out the repo).

## Caching, `zz_update`, and pinning an origin/ref

Both `setup.sh` and `zz_use`'s zz_* bundle install resolve the same way:
straight from disk when running inside a checkout of this repo, otherwise
from a local cache directory (`ZZ_CACHE_DIR/<org>/<repo>/<ref>`, default
`~/.cache/zz_scripts/tomgrv/scripts/main`) that's populated on first use
and then just linked from on every call after that — no repeat network
round-trip.

`zz_update` forces a fresh download, bypassing the cache, and re-links the
core `zz_*` scripts from it:

```sh
zz_update # or: zz_use --force <tool...>
```

Any tool name accepts an optional `[org/repo/]` prefix and/or `@<ref>`
suffix, to pull it from a different GitHub repo and/or pin it to a
specific tag, branch, or commit instead of this repo's own default
(`ZZ_ORIGIN`, default `tomgrv/scripts`; `ZZ_ORIGIN_REF`, default `main`):

```sh
zz_use validate-json@v2
zz_use someorg/otherscripts/some-tool@v1
```

Each origin+ref gets its own cache slot, so pinning one script doesn't
disturb anything already resolved at the default. A pinned or
other-origin request always (re)installs — unlike a plain, default-origin
request, it's never skipped just because a same-named command is already
on `PATH`, since there's no way to tell from an installed script alone
which repo/ref produced it.

## Naming

- **Core** folders keep the `zz_` prefix — each atomic function is its own
  dedicated script: `zz_use`, `zz_update`, `zz_colors`, `zz_log`, `zz_args`,
  `zz_prompt`, `zz_ask`, `zz_input`, `zz_bindir`, `zz_dispatch`, `zz_npx`,
  `zz_persist`, `zz_call`.
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
the actual resolving, calling `_bindir`, `_install_zz_bundle`,
`_install_repo_script`, etc. None of them need `zz_bindir`, `zz_log`, or
any other core script to already be on `PATH` — but that's not because
they each carry a fallback reimplementation. It's `_resolve_src` doing the
one thing that actually has to happen first: figure out the "tarball
context" (a checkout, a warm cache, or a freshly downloaded tarball — all
three are just a directory of `zz_*/run.sh` siblings) and symlink every
script in it onto `PATH` under its real name, in a throwaway scratch dir.
From that point on, `command -v zz_bindir`, `zz_log ...`, even the
`. zz_colors` _inside_ zz_bindir's and zz_log's own source, all just
resolve normally — zero reimplementation of what those scripts do. That's
what lets `zz_use` bootstrap the whole core `zz_*` bundle from nothing:
the very first `zz_use zz_colors ...` a freshly downloaded, standalone
`zz_use` ever runs (e.g. from `setup.sh`) needs none of its own
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

| Script                                   | Purpose                                                                                                                               |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `zz_use <tool>[@ref]`                    | the activator: resolve/install a dependency, if and only if missing (see below)                                                       |
| `zz_update`                              | force a fresh download of the zz_* bundle, bypassing the local cache                                                                  |
| `zz_colors`                              | ANSI color vars (`$Red` `$Green` ... `$End`); source it: `. zz_colors`                                                                |
| `zz_log <lvl> <msg...>`                  | colored, leveled log line on stderr (`i`/`w`/`e`/`s`/`-`)                                                                             |
| `zz_args <title> <caller> <<-help ...`   | parse `$@` per a spec; `eval $(zz_args ...)` to bind the vars                                                                         |
| `zz_prompt <question> [default]`         | interactive free-form input                                                                                                           |
| `zz_ask <options> <question...>`         | interactive single-char confirm                                                                                                       |
| `zz_input [file]`                        | read from arg (literal or file) or stdin                                                                                              |
| `zz_bindir [-t target]`                  | resolve/create a writable bin dir; `eval $(zz_bindir ...)` to bind `$dir` and extend `PATH`                                           |
| `zz_dispatch <caller> <subcmd>`          | dispatch an underscore-prefixed caller to a sibling `<name>-<subcmd>` script                                                          |
| `zz_npx [-s] <tool>`                     | run a local `node_modules/.bin` binary, falling back to `npx`                                                                         |
| `zz_persist [-f\|-p] <key> <value>`      | upsert a `KEY=VALUE` pair into an env file and/or `/etc/profile.d`                                                                    |
| `zz_call [-p package.json] [command...]` | resolve a caller's declared env vars (`config.input`/`config.output` in `package.json`; ask + persist if missing), then run a command |

## Functional scripts

| Script              | Purpose                                                                |
| ------------------- | ---------------------------------------------------------------------- |
| `load-json`         | load JSON from a file/URL, tag it with `$id`                           |
| `validate-json`     | validate JSON against a (local/inferred/remote) JSON Schema            |
| `normalize-json`    | sort JSON keys per schema + alphabetically, optional in-place write    |
| `merge-json`        | recursively merge one JSON file into another (arrays deduped, unioned) |
| `resolve-context`   | resolve a feature's source/target dirs from the calling script         |
| `edit-script`       | copy an installed script locally and open it for editing               |
| `distribute-utils`  | copy `zz_*`/utility scripts into a project's local scripts directory   |
| `install-feature`   | copy a feature's stubs/config/bin into a target, run `install-*.sh`    |
| `configure-feature` | deploy a feature's stubs into the cwd (merging), run `configure-*.sh`  |

See each folder's own `README.md` for its usage line.

## Git utilities

Migrated from `tomgrv/devcontainer-features`'s `gitutils` feature (which
used to ship them directly under `src/gitutils/bin/`), mirroring the same
move `common-utils`'s functional scripts made earlier — one source of
truth here, fetched on demand via `zz_use` instead of duplicated per
consumer. Installed as `git-<name>` on `PATH`, so git resolves them as
`git <name>` subcommands (e.g. `git-release-beta` → `git release-beta`).
The `gitutils` feature still owns the config (which aliases like `git
beta`/`git prod` point at which of these) and the git-flow install/config
lifecycle — only the script implementations moved.

| Script               | Purpose                                                     |
| -------------------- | ----------------------------------------------------------- |
| `git-align`          | align the current branch with its remote counterpart        |
| `git-autorebase`     | non-interactive rebasing with conflict resolution           |
| `git-co`             | enhanced commit                                             |
| `git-degit`          | clone and degit a repository                                |
| `git-fix`            | dispatch to `git-fix-<subcommand>`                          |
| `git-fix-author`     | set `user.name`/`user.email` to a specified commit's author |
| `git-fix-base`       | rebase commits from one branch onto another                 |
| `git-fix-blanks`     | discard whitespace/blank/quote-slash-only changes           |
| `git-fix-children`   | delete all descendant tags and branches of a commit         |
| `git-fix-date`       | fix commit dates/times in history                           |
| `git-fix-del`        | delete a specified commit and rebase subsequent history     |
| `git-fix-emoji`      | fix git emoji                                               |
| `git-fix-last`       | edit the last commit's message and content                  |
| `git-fix-lock`       | resolve conflicts and regenerate lock files                 |
| `git-fix-message`    | rewrite an arbitrary commit message                         |
| `git-fix-mode`       | fix file mode changes from diff                             |
| `git-fix-privacy`    | fix privacy in history                                      |
| `git-fix-prune`      | prune stale remote-tracking references                      |
| `git-fix-rights`     | set appropriate file/directory permissions                  |
| `git-fix-secrets`    | redact a secret across git history                          |
| `git-fix-up`         | amend a commit with current changes and rebase              |
| `git-forall`         | execute a command for all files in the repository           |
| `git-getcommit`      | list history and ask for a commit to fix up                 |
| `git-integrate`      | integrate modifications from the remote repository          |
| `git-pick`           | pick files from a specific commit                           |
| `git-release`        | dispatch to `git-release-<subcommand>`                      |
| `git-release-alpha`  | squash-merge the current feature branch into develop        |
| `git-release-beta`   | start a release branch via Git Flow                         |
| `git-release-hotfix` | start a hotfix branch via Git Flow                          |
| `git-release-prod`   | finish a release/hotfix branch via Git Flow                 |
| `git-unset`          | unset all git config keys starting with a given prefix      |
| `git-workspaces`     | list workspace directories and affected workspaces          |

## Usage

Install the whole workspace, or a single script's own package:

```sh
npm install --save-dev @tomgrv/scripts # everything
# or, e.g.:
npm install --save-dev ./validate-json # just this one, standalone
```

Every functional script is self-contained: `zz_use zz_colors zz_args ...`
resolves its own dependencies (installing the `zz_*` bundle and any
external tools on first use), then `. zz_colors` picks up the color vars.
Any single folder can be copied out and still work standalone.

## Tests

```sh
npm test                     # bats --recursive . (every */test.bats)
bats validate-json/test.bats # a single script's tests
```
