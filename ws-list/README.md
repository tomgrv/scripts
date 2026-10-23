<!-- @format -->

# ws-list

List workspace directories and affected workspaces.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `ws-list`.

## Usage

```sh
ws-list [-b] [-e <engine>] [-o] [-r <range>] [<dir>]
```

Workspace directories (`./<dir>`) of `<dir>` (default: the git toplevel, else
the current directory), from `workspaces` (array or `{packages: []}`).

- `-b` keeps workspaces with a `bin` file that exists
- `-e <engine>` keeps workspaces with an `engines.<engine>` entry
- `-o` sorts by `config.order` (default 1000), declaration order for ties
- `-r <range>` keeps only workspaces touched by the commits of the git range

`ws-list -b -e zz-setup -o` lists the runnable `zz-setup` workspaces.
`jq` is installed on demand when missing.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- falls back to listing all top-level directories with no `package.json`
- lists directories matching `package.json` workspaces globs
- lists a literal (non-glob) workspace entry
- `-r` reports only workspaces touched within a commit range
- `-r` prints nothing when the range touches no workspace
- `-b`, `-e`, `-o` filter and order by `package.json` fields
- a directory argument and the `workspaces.packages` form
