<!-- @format -->

# zz-menu

Interactive numbered CLI menu (keys, the same everywhere: a number acts on its item, Enter validates, `q` quits): draws the items, reads a choice, prints the
chosen key.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-menu`.

## Usage

```sh
zz-menu [-t title] [-d default] [-f footer] [-c states] <item>...
```

Each `<item>` is `<key>=<label>` (split at the first `=`), or just `<label>`,
which then doubles as its own key. The menu is drawn on stderr, so stdout
carries only the chosen key. A label may hold TAB-separated cells: the menu
aligns them in columns. On a terminal, up to 9 items take the number as one
keypress (no Enter) and cycling redraws the menu in place. An action that is
not one of the choices is just one more item, e.g. `"none=None"` last.

| Option           | Purpose                                                                           |
| ---------------- | --------------------------------------------------------------------------------- |
| `-t <title>`     | title line shown above the items                                                  |
| `-d <key>`       | key chosen when the user just presses Enter                                       |
| `-f <text>`      | hint line replacing the default one (`\n` starts a new line)                      |
| `-g <n>`         | group by the n-th TAB-separated cell (as `cut -f`): items are regrouped in order of first appearance under a header per group, that cell is not repeated on the rows; an item with a single cell stays outside any group |
| `-c <states>`    | cycle mode: comma-separated states, see below                                     |

| Exit status | Meaning                                                 |
| ----------- | ------------------------------------------------------- |
| `0`         | an item was chosen; its key is on stdout                |
| `1`         | the user quit (`q`) or input ended                      |
| `2`         | bare Enter with no default — the caller's "proceed" cue |

`q` leaves the menu without choosing and never aborts the caller's run: a sub-menu goes back or keeps what is set (`zz-vars`, `vps-access`); only the top-level `zz-setup` workspace menu treats it as "cancel everything". Tests drive any menu or prompt with `ZZ_PROMPT_ANSWERS=<file>` (one answer per line, see `zz-prompt`).

### Single choice

```sh
action=$(zz-menu -t "Action" "start=Start" "stop=Stop") || exit 1
```

### Loop until the user is done

```sh
while :; do
    rc=0
    choice=$(zz-menu -t "Steps" "a=Alpha [on]" "b=Beta [off]") || rc=$?
    [ "$rc" -eq 1 ] && exit 0   # quit
    [ "$rc" -eq 2 ] && break    # proceed
    # ... toggle $choice, then redraw
done
```

### Cycle mode

With `-c "s1,s2,..."` every item carries a state, shown as `[state]`.
Choosing a number advances that item to the next state (wrapping around)
and redraws (a state that differs from where it started is highlighted), so the caller needs no loop of its own. Items are
`<key>:<state>=<label>`; without `:<state>` an item starts at the first state.
Enter prints one `<key>=<state>` line per item and exits `0`; `q` (or end of
input) exits `1` and prints nothing.

```sh
out=$(zz-menu -t "Steps" -c "skip,up,down" "web:up=Web server" "db=Database") || exit 0
printf '%s\n' "$out"   # web=up / db=skip, after the user's changes
```

## Dependencies

`zz-args`, `zz-colors`, `zz-log` — declared as `peerDependencies` in
`package.json` and resolved on demand by `zz-use`.

## Tests

```sh
bats test.bats
```

- choosing by number prints the item's key (or its label when it has no `=`)
- bare Enter prints the default key, or exits 2 without one
- `q` and end of input exit 1 (no endless re-prompt)
- non-numeric and out-of-range input re-prompts with a warning
- the menu is drawn on stderr, never stdout
- `-f` footers may span several lines (`\n`)
- cycle mode: states advance and wrap, Enter prints every `key=state`,
  `q` prints nothing, out-of-range input changes nothing, changed states are highlighted
- TAB-separated cells are aligned in columns
