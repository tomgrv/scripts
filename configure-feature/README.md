# configure-feature

Deploy a feature's stubs into the cwd (merging), run configure-*.sh.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `configure-feature`.

## Usage

```sh
configure-feature [-s source] <feature>
```

## `.clean` files

A `.clean` file placed anywhere under a feature's `stubs/` directory lists
legacy files to retire on deployment, one directive per line, paths relative
to the repo root (same addressing as any other stub target):

```
RMV path/to/legacy-file
DEL path/to/obsolete-file
KEY package.json ["lint-staged","legacy-glob"]
```

- `RMV <path>` — untrack the file from git (`git rm --cached`), keeping it
  on disk (e.g. it moved from tracked to `.gitignore`d).
- `DEL <path>` — delete the file from disk and untrack it from git.
- `KEY <json-file> <path>` — remove one key from a JSON file. JSON stubs are
  merged with `merge-json`, which only ever adds keys, so a key a stub
  renamed or dropped would otherwise stay in every consumer's file forever.
  `<path>` is a JSON array of keys (strings, or numbers for array indexes),
  e.g. `["lint-staged","!(*schema).json"]`; it is handed to `jq` as data, not
  evaluated, so keys full of glob characters are safe. The file path cannot
  contain spaces. Nothing happens when the file or the key is missing, and a
  file that is not valid JSON is left untouched with a warning. The file is
  rewritten with the feature's 4-space indentation.

Blank lines and lines starting with `#` are ignored. `.clean` itself is never
deployed as a stub.

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
- replaces an existing file wholesale when the stub opens with `---` frontmatter
- strips leading `_` prefix and `.gitignore`s `#`-prefixed stub destinations
- preserves executable bits and symlinks stub targets
- processes `.clean` RMV/DEL/KEY directives, skips deploying `.clean` itself
- runs `configure-*.sh` scripts only from the repo top level
