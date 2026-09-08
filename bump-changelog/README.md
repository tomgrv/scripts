<!-- @format -->

# bump-changelog

Generate a `CHANGELOG.md` entry from conventional commits since the last tag
(or rebuild the whole changelog from all tags with `-r`), optionally bumping
version files (`-b`, delegates to [`bump-version`](../bump-version)) and
creating a tag (`-t`, delegates to [`bump-tag`](../bump-tag)).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `bump-changelog`.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
