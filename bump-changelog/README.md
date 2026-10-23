<!-- @format -->

# bump-changelog

Generate a `CHANGELOG.md` entry from conventional commits since the last tag
(or rebuild the whole changelog from all tags with `-r`), optionally bumping
version files (`-b`, delegates to [`bump-version`](../bump-version)) and
creating a tag (`-t`, delegates to [`bump-tag`](../bump-tag)).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `bump-changelog`.

## Usage

```sh
bump-changelog [-f <version>] [-b] [-m] [-d] [-t] [-r] [-s <scope>] <file>
```

| Argument       | Effect                                                                     |
| -------------- | -------------------------------------------------------------------------- |
| `-f <version>` | Force version for changelog entry                                          |
| `-b`           | Bump version files as per commit-and-tag-version.bumpFiles in package.json |
| `-m`           | Only bump workspace files if commit scope relates to workspace name        |
| `-d`           | Show what would be added without making changes                            |
| `-t`           | Create git tag for version                                                 |
| `-r`           | Rebuild entire changelog from all git history                              |
| `-s <scope>`   | Limit changelog to specific scope                                          |
| `<file>`       | File to write changelog to (default: CHANGELOG.md)                         |

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
