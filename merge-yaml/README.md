# merge-yaml

Recursively merge one YAML file into another, arrays deduped and unioned.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `merge-yaml`. Mirrors `merge-json`'s semantics
(same recursive-merge/array-dedupe rules): jq computes the merged values
from a JSON view of both files, then yq overlays them onto the original
target (`yq ea 'select(fi == 0) * select(fi == 1)'`, see yq's
[tips and tricks](https://mikefarah.gitbook.io/yq/usage/tips-and-tricks)),
so the target's comments, key order and flow/block styles are kept.

Array elements that are objects are reconciled by identity: elements sharing
the same `id` (or, when there is no `id`, the same `name`) are merged into one
entry instead of duplicated. Elements with neither key are deduped by equality.

## Usage

```sh
merge-yaml [-i indent] <target> <source>
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

Requires [mikefarah/yq](https://github.com/mikefarah/yq) v4 (Go). When no
`yq` is on `PATH`, `zz_use yq` downloads the pinned release binary. A
different `yq` already on `PATH` (e.g. apt's python kislyuk/yq) is rejected
with an explicit error rather than silently shadowed.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- errors with no arguments, only a target, or a missing target file
- errors when the target file is not valid YAML, showing yq's parse error
- errors clearly when `yq` is not mikefarah/yq
- keeps a GitHub workflow `on:` key unquoted
- merges a source object into the target file in place
- merges from stdin when source is `-`
- unions and dedupes array values, recursively merges nested objects
- keeps the target's comments, key order and flow style
- keeps target values on scalar and type conflicts
- fills an empty target from the source
- writes 2-space indents by default, honours `-i` otherwise
