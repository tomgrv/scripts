# feature-configure

Deploy a feature's stubs into the cwd (merging), run configure-*.sh.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `feature-configure`.

## Usage

```sh
feature-configure [-s source] <feature>
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
- `KEY <file> <path>` — remove one key from a JSON or YAML file. The stub
  merges (`json-merge`, `yaml-merge`) only ever add keys and keep the value
  already in the target, so a key a stub renamed or dropped, or a scalar a stub
  fixed, would otherwise stay as it was in every consumer's file forever.
  `<path>` is a JSON array of steps, handed to `jq`/`yq` as data and never
  evaluated, so keys full of glob characters are safe:
    - a string is an object key;
    - a number is an array index;
    - an object such as `{"name":"Deploy"}` selects the first array element
      whose fields all match, the way `yaml-merge` identifies list items.

    ```
    KEY package.json ["lint-staged","legacy-glob"]
    KEY .github/workflows/review.yml ["jobs","review","if"]
    KEY .github/workflows/sync.yml ["jobs","sync","steps",{"name":"Create PR"},"with","repository"]
    ```

    `KEY` runs **before** the stubs are merged. If the stub still has the key,
    the merge then writes the stub's current value in place of the old one (a
    fixed scalar is replaced); if the stub no longer has it, the key stays gone.
    Nothing happens when the file or the key is missing, so it is idempotent. A
    file that is not valid JSON or YAML, a malformed path, or a YAML file when
    `mikefarah/yq` is not installed is left untouched with a warning. JSON files
    are rewritten with 4-space indentation, YAML files keep their comments. The
    file path cannot contain spaces. Prefer an object selector over an index for
    array elements, since an index can point at a different element in a file the
    consumer edited.

Blank lines and lines starting with `#` are ignored. `.clean` itself is never
deployed as a stub.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
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
