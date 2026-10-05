# zz_menu

Interactive numbered CLI menu: draws the items, reads a choice, prints the
chosen key.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_menu`.

## Usage

```sh
zz_menu [-t title] [-d default] [-f footer] <item>...
```

Each `<item>` is `<key>=<label>` (split at the first `=`), or just `<label>`,
which then doubles as its own key. The menu is drawn on stderr, so stdout
carries only the chosen key.

| Option       | Purpose                                              |
| ------------ | ---------------------------------------------------- |
| `-t <title>` | title line shown above the items                     |
| `-d <key>`   | key chosen when the user just presses Enter          |
| `-f <text>`  | hint line replacing the default one under the items  |

| Exit status | Meaning                                                  |
| ----------- | -------------------------------------------------------- |
| `0`         | an item was chosen; its key is on stdout                 |
| `1`         | the user quit (`q`) or input ended                       |
| `2`         | bare Enter with no default — the caller's "proceed" cue  |

### Single choice

```sh
action=$(zz_menu -t "Action" "start=Start" "stop=Stop") || exit 1
```

### Loop until the user is done

```sh
while :; do
    rc=0
    choice=$(zz_menu -t "Steps" "a=Alpha [on]" "b=Beta [off]") || rc=$?
    [ "$rc" -eq 1 ] && exit 0   # quit
    [ "$rc" -eq 2 ] && break    # proceed
    # ... toggle $choice, then redraw
done
```

## Dependencies

`zz_args`, `zz_colors`, `zz_log` — declared as `peerDependencies` in
`package.json` and resolved on demand by `zz_use`.

## Tests

```sh
bats test.bats
```

- choosing by number prints the item's key (or its label when it has no `=`)
- bare Enter prints the default key, or exits 2 without one
- `q` and end of input exit 1 (no endless re-prompt)
- non-numeric and out-of-range input re-prompts with a warning
- the menu is drawn on stderr, never stdout
