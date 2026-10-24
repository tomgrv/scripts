<!-- @format -->

# bump-tag

Create or move a version tag (defaulting to the version `gitversion` computes),
plus its dependent major and major.minor tags, then push all three to the
remote.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `bump-tag`.

## Usage

```sh
bump-tag [-f] [-p] [-b <blame>] <tag>
```

| Argument     | Effect                                                                                                    |
| ------------ | --------------------------------------------------------------------------------------------------------- |
| `-f`         | Force tag creation even if it exists                                                                      |
| `-p`         | Prefix to use for the tag (default: v)                                                                    |
| `-b <blame>` | Tag the last commit where the version field in the specified JSON file was changed to the current version |
| `<tag>`      | Tag to create or follow                                                                                   |

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list. Also
assumes a `gitversion` CLI on `PATH` when no explicit tag is given — see
[`gv`](../gv).

## Tests

```sh
bats test.bats
```
