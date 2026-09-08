# configure-feature

Deploy a feature's stubs into the cwd (merging), run configure-*.sh.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `configure-feature`.

## Usage

```sh
configure-feature [-s source] <feature>
```

## `.clean`

A `.clean` file at a feature's root (alongside `stubs/`, `config/`, `bin/`)
lists legacy files to retire on deployment, one directive per line, paths
relative to the repo root:

```
RMV path/to/legacy-file
DEL path/to/obsolete-file
```

- `RMV <path>` — untrack the file from git (`git rm --cached`), keeping it
  on disk (e.g. it moved from tracked to `.gitignore`d).
- `DEL <path>` — delete the file from disk and untrack it from git.

Blank lines and lines starting with `#` are ignored. `install-feature`
copies `.clean` alongside `stubs/`/`config/`/`bin/`; `configure-feature`
processes it after deploying stubs.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- errors without a feature argument, or when source doesn't exist
- copies a new plain-text stub, merges a json stub into an existing file
- reconciles a text fragment additively into an existing file
- strips leading `_` prefix and `.gitignore`s `#`-prefixed stub destinations
- preserves executable bits and symlinks stub targets
- processes `.clean` RMV/DEL directives from the feature root
- runs `configure-*.sh` scripts only from the repo top level
